package com.orbix.pixora.scene

import android.content.Context
import android.graphics.Canvas
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
        loadedFor = sceneId
        spec = parsed
        Log.d(TAG, "Loaded scene '$sceneId' (${parsed.sprites.size} sprites, " +
            "${parsed.particles.size} particles, ${parsed.events.size} events)")
        return true
    }

    /** Lazy-load all SpriteSheets the spec needs from filesDir. */
    fun ensureLoaded() {
        val s = spec ?: return
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

    /** Per-frame draw. Background is drawn by PixoraWallpaperService BEFORE this. */
    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        if (spec == null) return
        ensureLoaded()
        tick++

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

        // Sprites
        for (c in spriteControllers) c.draw(canvas, surfaceWidth, surfaceHeight, tick)

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
        spec = null
        loadedFor = null
    }

    companion object {
        private const val TAG = "CanvasScene"
    }
}
