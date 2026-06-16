package com.orbix.pixora.scene

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.util.Log
import com.orbix.pixora.renderers.SpriteSheet
import java.io.File

/**
 * Generic Canvas-based renderer driven by a SceneSpec JSON.
 *
 * Replaces hardcoded renderers (VolcanoRenderer, DuskFortressRenderer)
 * with a single engine that interprets the spec. Adding a new wallpaper
 * of this type = upload spec JSON + sprite ZIPs, NO Kotlin recompile.
 *
 * Lifecycle:
 *   1. loadSpec(sceneId)      ← reads filesDir/scene_specs/<id>.json
 *   2. ensureLoaded()         ← lazy-loads SpriteSheets from filesDir
 *   3. draw(canvas) per frame ← runs particles, sprites, events in order
 *   4. release()              ← recycles bitmaps
 */
class CanvasSceneRenderer(private val context: Context) {

    var surfaceWidth = 0
    var surfaceHeight = 0

    private var spec: SceneSpec? = null
    private var loadedFor: String? = null  // sceneId of currently loaded spec
    private var tick = 0L

    // Active sub-systems (rebuilt when spec changes)
    private val sheets = mutableMapOf<String, SpriteSheet>()
    private val spriteControllers = mutableListOf<SpriteController>()
    private val particleSystems = mutableListOf<ParticleSystem>()
    private val events = mutableListOf<SceneEvent>()
    private val layerBitmaps = mutableListOf<Pair<ImageLayerDef, Bitmap>>()
    private val layerPaint = Paint(Paint.FILTER_BITMAP_FLAG)

    // Layer pre-scaling — see ensureLayersPrescaled().
    // We track surface dimensions so we re-prescale if the surface is recreated
    // at a different size (rare, but happens on rotation / fold). The flag also
    // prevents redundant prescaling work each frame.
    private var prescaledForW = 0
    private var prescaledForH = 0

    /** Latest gyroscope-driven offset in pixels (set by PixoraWallpaperService). */
    @Volatile var tiltX: Float = 0f
    @Volatile var tiltY: Float = 0f

    /** Horizontal scroll state — same algorithm as the panoramic wallpaper:
     *    1. Touch MOVE events feed `scrollVelocity` (norm-per-frame) AND
     *       nudge `targetScrollOffsetNorm`.
     *    2. Per draw frame we add velocity to target and decay by 0.92,
     *       so motion continues after the finger lifts (inertia / fling).
     *    3. `scrollOffsetNorm` lerps toward target at 0.15 — what actually
     *       gets drawn. Two-stage smoothing = buttery flow even when the
     *       launcher only delivers a few sparse onOffsetsChanged events. */
    @Volatile var scrollOffsetNorm: Float = 0.5f
    @Volatile var targetScrollOffsetNorm: Float = 0.5f
    val scrollSettling: Boolean
        get() = kotlin.math.abs(targetScrollOffsetNorm - scrollOffsetNorm) > 0.0015f

    /** True when the scene has its own image_layers (so wallpaper service skips bg draw). */
    val hasParallax: Boolean get() = spec?.hasParallax == true

    /** True when any image_layer declares bob animation. Wallpaper service
     *  uses this to keep the draw loop at video-rate (~16-30fps) even when
     *  the device is idle — otherwise idleMode caps us at 1fps and the bob
     *  becomes invisible (slow giant jumps instead of smooth float). */
    val hasBobAnimation: Boolean
        get() = spec?.imageLayers?.any { it.bobAmplitudePx > 0f } == true
    // The Pixora "P" 3D logo signature is owned globally by
    // PixoraWallpaperService so it appears on every wallpaper, not only
    // canvas_scenes. CanvasSceneRenderer just exposes spec.branding
    // overrides for the scenes that want to relocate it.
    val brandingOverride: org.json.JSONObject? get() = spec?.brandingJson

    /** Currently-loaded scene id, or null if none. */
    val currentSceneId: String? get() = loadedFor

    /**
     * Load a scene spec by its id. Reads from filesDir/scene_specs/<id>.json
     * (which Dart's SceneSpecService writes). Returns true on success.
     */
    fun loadSpec(sceneId: String): Boolean {
        if (loadedFor == sceneId && spec != null) return true
        val f = File(context.filesDir, "scene_specs/$sceneId.json")
        if (!f.isFile) {
            Log.w(TAG, "Scene spec not found: ${f.absolutePath}")
            return false
        }
        val parsed = SceneSpec.fromFile(f) ?: run {
            Log.w(TAG, "Scene spec parse failed: $sceneId")
            return false
        }
        // Tear down old subsystems (preserve sprite bitmaps if reused below)
        spriteControllers.clear()
        particleSystems.clear()
        events.clear()
        for ((_, b) in layerBitmaps) if (!b.isRecycled) b.recycle()
        layerBitmaps.clear()
        // Same fix as in release() — fresh bitmaps need a fresh prescale.
        prescaledForW = 0
        prescaledForH = 0
        loadedFor = sceneId
        spec = parsed
        Log.d(TAG, "Loaded scene '$sceneId' (${parsed.sprites.size} sprites, " +
            "${parsed.particles.size} particles, ${parsed.events.size} events)")
        return true
    }

    /** Lazy-load all SpriteSheets the spec needs from filesDir. */
    fun ensureLoaded() {
        val s = spec ?: return
        // Load image layers (parallax) — read from filesDir/scene_layers/<id>/<key>.webp
        if (layerBitmaps.isEmpty() && s.imageLayers.isNotEmpty()) {
            val layerDir = File(context.filesDir, "scene_layers/${s.id}")
            for (layer in s.imageLayers.sortedBy { it.z }) {
                val f = File(layerDir, "${layer.key}.webp")
                if (!f.isFile) {
                    Log.w(TAG, "Image layer file missing: ${f.absolutePath}")
                    continue
                }
                val bmp = BitmapFactory.decodeFile(f.absolutePath)
                if (bmp != null) {
                    layerBitmaps.add(layer to bmp)
                    Log.d(TAG, "Loaded layer ${layer.key} ${bmp.width}x${bmp.height} pf=${layer.parallaxFactor}")
                }
            }
        }
        // Load all sprite manifest_keys (each used by 0+ controllers/events).
        // Fullscreen sprites use sampleSize=1 to keep all source detail
        // (otherwise the 2x decode downscale + later upscale = mush).
        for (sp in s.sprites) {
            sheets.getOrPut(sp.name) {
                val isFullscreen = sp.params.optBoolean("fullscreen", false)
                SpriteSheet(context, sp.manifestKey).also {
                    if (!it.loaded) it.load(
                        framesPerTick = sp.frameSkip,
                        sampleSize = if (isFullscreen) 1 else 2,
                    )
                }
            }
        }
        // Events may reference sprites by name; sheet was created above.
        // (If a sprite is ONLY used by an event, declare it in spec.sprites
        //  with behavior:"static" + scale:0 — or extend spec with a
        //  "preload_only" sprite list. For now we require the sprite to
        //  appear in the sprites list to be loaded.)

        // Build controllers + systems if not built yet
        if (spriteControllers.isEmpty() && s.sprites.isNotEmpty()) {
            for (sp in s.sprites) {
                val sheet = sheets[sp.name] ?: continue
                SpriteController.create(sp, sheet)?.let { spriteControllers.add(it) }
            }
        }
        if (particleSystems.isEmpty() && s.particles.isNotEmpty()) {
            for (p in s.particles) {
                ParticleSystem.create(p)?.let { particleSystems.add(it) }
            }
        }
        if (events.isEmpty() && s.events.isNotEmpty()) {
            for (e in s.events) {
                SceneEvent.create(e)?.let { events.add(it) }
            }
        }
    }

    /** Per-frame draw. Background is drawn by PixoraWallpaperService BEFORE this,
     *  EXCEPT when this scene has image_layers (then bg is skipped and we draw
     *  layers here in z-order with gyroscope-driven parallax offsets). */
    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        if (spec == null) return
        ensureLoaded()
        // PERF (2026-06-06): pre-scale layer bitmaps to cover-fit dimensions
        // ONCE per surface size. Was the #1 wallpaper perf killer — every
        // frame did `drawBitmap(bmp, null, dst)` which forces bilinear scaling
        // per pixel × 4 layers × 1080×2340 = ~250M ops/frame on Mali → 3 fps
        // on Eduardo's Samsung. Now per-frame cost is a pure blit (essentially
        // free on hardware Canvas). One-time scaling cost ~200-400ms on first
        // visible frame; insignificant vs the savings of every subsequent frame.
        ensureLayersPrescaled()
        tick++

        // Direct one-shot follow — same model Samsung's ImageWallpaper
        // uses for static panoramic wallpapers. Each onOffsetsChanged
        // event from the launcher snaps to its xOffset; no lerp delay.
        // Smoothness comes from event frequency (Samsung sends many per
        // swipe when it considers us scrollable, which it now does
        // thanks to suggestDesiredDimensions(2*W, H) + SET_WALLPAPER_HINTS).
        scrollOffsetNorm = targetScrollOffsetNorm

        // Parallax image layers (drawn first — behind everything else)
        if (layerBitmaps.isNotEmpty()) {
            for ((def, bmp) in layerBitmaps) {
                if (bmp.isRecycled) continue
                drawLayerCentered(canvas, bmp, def)
            }
        }

        for (p in particleSystems) p.draw(canvas, surfaceWidth, surfaceHeight, tick)

        // Draw "behind sprites" events (lightning_procedural, flash_overlay)
        for (e in events) {
            if (e is LightningProceduralEvent || e is FlashOverlayEvent) {
                e.draw(canvas, surfaceWidth, surfaceHeight, tick, sprite = null)
            }
        }

        // Sprites — sprites in parallax scenes inherit the layer offset matching
        // their declared parallax_factor (read from sprite params, default 1.0
        // so the sprite stays "stuck" to the foreground layer e.g. orb in hands).
        for (c in spriteControllers) {
            val pf = c.def.params.f("parallax_factor", 1f)
            if (pf > 0.001f) {
                canvas.save()
                canvas.translate(tiltX * pf, tiltY * pf)
                c.draw(canvas, surfaceWidth, surfaceHeight, tick)
                canvas.restore()
            } else {
                c.draw(canvas, surfaceWidth, surfaceHeight, tick)
            }
        }

        // Hero events on top (phoenix, lightning_sprite, bat_swarm)
        for (e in events) {
            when (e) {
                is PhoenixEvent, is LightningSpriteEvent, is BatSwarmEvent -> {
                    val sprite = e.spriteName?.let { sheets[it] }
                    e.draw(canvas, surfaceWidth, surfaceHeight, tick, sprite)
                }
                else -> Unit  // already drawn in pre-sprite pass
            }
        }

        // Pixora "P" 3D logo is drawn by PixoraWallpaperService (universal).
    }

    /** Draw a layer bitmap on the surface with cover-fit + parallax offset.
     *
     *  Combines TWO offsets per layer:
     *    1. **Tilt** (gyro)   — scaled by parallax_factor for 3D depth feel
     *    2. **Scroll** (home page swipe) — scaled by parallax_factor too, so
     *       deeper layers (low pf) barely scroll while foreground layers
     *       slide in sync with home page swipes.
     *
     *  When the bitmap is wider than the surface (oversized), the scroll
     *  offset pans across the extra horizontal slack — just like a panoramic
     *  wallpaper but per-layer with its own depth speed. */
    private fun drawLayerCentered(canvas: Canvas, bmp: Bitmap, def: ImageLayerDef) {
        // POST-PRESCALE FAST PATH: the bitmap was already scaled to cover-fit
        // dimensions in ensureLayersPrescaled(). bmp.width/height ARE the
        // target drawW/drawH, so we skip the per-frame scale multiplication
        // and use the 3-arg drawBitmap (pure blit, no bilinear filtering).
        val sw = surfaceWidth.toFloat()
        val sh = surfaceHeight.toFloat()
        val drawW = bmp.width.toFloat()
        val drawH = bmp.height.toFloat()
        val pf = def.parallaxFactor
        val sf = def.scrollFactor

        // Horizontal SCROLL (home page swipes): pans across bitmap's extra width.
        val extraW = (drawW - sw).coerceAtLeast(0f)
        val scrollOffset = (0.5f - scrollOffsetNorm) * extraW * sf

        // Standalone organic float — sums two sinusoids whose periods differ
        // by the golden ratio (~1.618), an irrational number. That means the
        // combined wave NEVER repeats exactly, so the subject drifts in a
        // pattern the eye can't predict — looks like a real object suspended
        // in water/air instead of a robot bouncing on a metronome.
        //
        // Horizontal drift uses a different period+ratio so X and Y motion
        // are decoupled (Lissajous-like). Result: tiny, organic 2D float.
        //
        // Key is hashed into the phase so multiple bobbing layers don't
        // start at the same point in their cycle.
        var bobOffsetX = 0f
        var bobOffsetY = 0f
        if (def.bobAmplitudePx > 0f) {
            val tSec = System.nanoTime().toDouble() / 1_000_000_000.0
            val phaseShift = (def.key.hashCode() and 0xff) / 256.0
            val p = def.bobPeriodSec.toDouble()
            val twoPi = 2.0 * Math.PI

            // Vertical: compound wave (primary + golden-ratio harmonic)
            val phaseY1 = ((tSec / p) + phaseShift) % 1.0
            val phaseY2 = ((tSec / (p * 1.618)) + phaseShift + 0.27) % 1.0
            val composedY = 0.62 * kotlin.math.sin(phaseY1 * twoPi) +
                            0.38 * kotlin.math.sin(phaseY2 * twoPi)
            bobOffsetY = (composedY * def.bobAmplitudePx).toFloat()

            // Horizontal: subtle drift at ~35% of Y amplitude, slower period,
            // golden-ratio harmonic too. Decoupled phase = organic 2D path.
            val periodX = p * 1.37
            val phaseX1 = ((tSec / periodX) + phaseShift + 0.41) % 1.0
            val phaseX2 = ((tSec / (periodX * 1.618)) + phaseShift + 0.83) % 1.0
            val composedX = 0.62 * kotlin.math.sin(phaseX1 * twoPi) +
                            0.38 * kotlin.math.sin(phaseX2 * twoPi)
            bobOffsetX = (composedX * def.bobAmplitudePx * 0.35).toFloat()
        }

        // Vertical/horizontal TILT (gyro): per-layer depth using parallax_factor
        val left = (sw - drawW) / 2f + tiltX * pf + scrollOffset + bobOffsetX
        val top  = (sh - drawH) / 2f + tiltY * pf + bobOffsetY
        canvas.drawBitmap(bmp, left, top, layerPaint)  // pure blit, ~free
    }

    /**
     * Pre-scale all layer bitmaps to cover-fit dimensions for the current
     * surface size. Runs at most once per (surfaceWidth, surfaceHeight) pair.
     *
     * BEFORE this optimization: every drawFrame() invoked drawBitmap with a
     * dst RectF different from bitmap dimensions → Mali GPU performed
     * bilinear filtering across all pixels (~250M ops/frame for 4 layers).
     * Eduardo's mid-range Samsung clocked 3 fps on Goku Genkidama.
     *
     * AFTER: layers are scaled ONCE at first valid surface, then per-frame
     * cost is a pure 2-arg drawBitmap (hardware-accelerated blit, essentially
     * free). Trades ~200-400ms one-time cost on first visible frame for
     * sustained 25-30 fps thereafter.
     *
     * Memory cost: prescaled layers replace originals in [layerBitmaps]; we
     * recycle the originals so net memory is similar or slightly LOWER
     * (originals are often larger than surface).
     */
    private fun ensureLayersPrescaled() {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        if (prescaledForW == surfaceWidth && prescaledForH == surfaceHeight) return
        if (layerBitmaps.isEmpty()) {
            // Don't cache the surface dimensions here — if layers load later
            // we WANT to re-enter and prescale. Just bail without recording.
            return
        }
        val sw = surfaceWidth.toFloat()
        val sh = surfaceHeight.toFloat()
        val newList = ArrayList<Pair<ImageLayerDef, Bitmap>>(layerBitmaps.size)
        var scaledCount = 0
        for ((def, bmp) in layerBitmaps) {
            if (bmp.isRecycled) continue
            // Per-layer `scale` (default 1.0) lets a foreground layer (e.g.
            // Goku) shrink to occupy less of the surface, revealing the layer
            // behind it. Multiplied INTO the cover-fit scale so prescale
            // already accounts for it → per-frame draw stays a pure blit.
            val scale = maxOf(sw / bmp.width, sh / bmp.height) * def.scale
            val targetW = (bmp.width * scale).toInt().coerceAtLeast(1)
            val targetH = (bmp.height * scale).toInt().coerceAtLeast(1)
            val scaled = if (targetW == bmp.width && targetH == bmp.height) {
                bmp  // already exactly right size
            } else {
                try {
                    val s = Bitmap.createScaledBitmap(bmp, targetW, targetH, true)
                    if (s !== bmp) {
                        bmp.recycle()
                        scaledCount++
                    }
                    s
                } catch (e: OutOfMemoryError) {
                    // Fallback: keep original; per-frame scaling will still
                    // work (slow) but at least we don't crash on low-RAM.
                    Log.w(TAG, "Layer prescale OOM for ${def.key} → ${targetW}x${targetH}, keeping original")
                    bmp
                }
            }
            newList.add(def to scaled)
        }
        layerBitmaps.clear()
        layerBitmaps.addAll(newList)
        prescaledForW = surfaceWidth
        prescaledForH = surfaceHeight
        Log.d(TAG, "Layers prescaled for ${surfaceWidth}x${surfaceHeight} (${scaledCount}/${newList.size} rescaled)")
    }

    fun reset() {
        tick = 0
        for (p in particleSystems) p.reset()
        for (e in events) e.reset()
    }

    fun release() {
        spriteControllers.clear()
        particleSystems.clear()
        events.clear()
        for (s in sheets.values) s.release()
        sheets.clear()
        for ((_, b) in layerBitmaps) if (!b.isRecycled) b.recycle()
        layerBitmaps.clear()
        spec = null
        loadedFor = null
        // 2026-06-06 BUG FIX: invalidate prescale flag so the NEXT load gets
        // fresh prescaling. Without this, fresh-loaded full-size bitmaps in
        // layerBitmaps don't get rescaled (because flag matches surface dims
        // from prior life of this renderer) → Goku draws at full 1300x2600
        // instead of the spec's scale=0.78 target. Manifested as: "se aleja
        // pero se vuelve a acercar" — preview engine prescaled correctly,
        // active engine reloaded after release() and never rescaled.
        prescaledForW = 0
        prescaledForH = 0
    }

    companion object {
        private const val TAG = "CanvasScene"
    }
}
