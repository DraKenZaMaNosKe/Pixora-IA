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

        // Order: particles first (they're "behind" sprites), then events
        // that should appear behind sprites (lightning), then sprites, then
        // hero events on top (phoenix, flash overlay).
        // For simplicity now we run them in spec declaration order.
        // Each system handles its own visibility/timing.
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
        val sw = surfaceWidth.toFloat()
        val sh = surfaceHeight.toFloat()
        val bw = bmp.width.toFloat()
        val bh = bmp.height.toFloat()
        val pf = def.parallaxFactor
        val sf = def.scrollFactor

        // Cover fit: scale by max ratio so bitmap fully covers surface
        val scale = maxOf(sw / bw, sh / bh)
        val drawW = bw * scale
        val drawH = bh * scale

        // Horizontal SCROLL (home page swipes): pans across bitmap's extra width.
        // Uses scrollFactor (independent from parallax). With scrollFactor=1.0
        // and a wide bitmap, scrolls full panoramic-style. With 0.0, layer is
        // locked to screen center regardless of home page.
        val extraW = (drawW - sw).coerceAtLeast(0f)
        val scrollOffset = (0.5f - scrollOffsetNorm) * extraW * sf

        // Vertical/horizontal TILT (gyro): per-layer depth using parallax_factor
        val left = (sw - drawW) / 2f + tiltX * pf + scrollOffset
        val top  = (sh - drawH) / 2f + tiltY * pf
        val dst = android.graphics.RectF(left, top, left + drawW, top + drawH)
        canvas.drawBitmap(bmp, null, dst, layerPaint)
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
    }

    companion object {
        private const val TAG = "CanvasScene"
    }
}
