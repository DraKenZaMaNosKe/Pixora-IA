package com.orbix.pixora.scene

import android.graphics.Color
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Parsed canvas_scene spec. Mirror of docs/schemas/scene_v1.md.
 *
 * The JSON arrives via SceneSpecService (Dart side) which writes it to
 * filesDir/scene_specs/<id>.json. The Kotlin renderer reads + parses on
 * scene activation.
 *
 * Only the fields used by CanvasSceneRenderer are exposed; unrecognized
 * vocabulary is ignored at parse time (CapabilityRegistry already
 * filtered the catalog, but defensive parsing keeps us safe).
 */
data class SceneSpec(
    val id: String,
    val schemaVersion: Int,
    val type: String,
    val backgroundUrl: String?,
    val backgroundScroll: Boolean,
    /** Optional parallax image layers drawn in z-order. Each layer can have
     *  its own gyroscope-driven parallax_factor. When non-empty, the wallpaper
     *  service skips the standard bg draw and these are used instead. */
    val imageLayers: List<ImageLayerDef>,
    val sprites: List<SpriteDef>,
    val particles: List<ParticleDef>,
    val events: List<EventDef>,
    /** Frame cycles — groups of image_layers whose alphas are time-multiplexed.
     *  Used for face blink, fire flicker, traffic light, etc. (v1.7.41). */
    val cycles: List<CycleDef>,
    /** Optional per-scene overrides for the BrandingLogo (P 3D signature). */
    val brandingJson: JSONObject?,
) {
    val hasParallax: Boolean get() = imageLayers.isNotEmpty()

    companion object {
        private const val TAG = "SceneSpec"

        fun fromFile(f: File): SceneSpec? = try {
            parse(JSONObject(f.readText()))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read ${f.name}: $e")
            null
        }

        fun parse(j: JSONObject): SceneSpec? = try {
            SceneSpec(
                id = j.getString("id"),
                schemaVersion = j.optInt("schema_version", 1),
                type = j.getString("type"),
                backgroundUrl = j.optJSONObject("background")?.optString("url"),
                backgroundScroll = j.optJSONObject("background")
                    ?.optBoolean("scroll", false) ?: false,
                imageLayers = parseList(j.optJSONArray("image_layers")) {
                    ImageLayerDef.parse(it)
                },
                sprites = parseList(j.optJSONArray("sprites")) {
                    SpriteDef.parse(it)
                },
                particles = parseList(j.optJSONArray("particles")) {
                    ParticleDef.parse(it)
                },
                events = parseList(j.optJSONArray("events")) {
                    EventDef.parse(it)
                },
                cycles = parseList(j.optJSONArray("cycles")) {
                    CycleDef.parse(it)
                },
                brandingJson = j.optJSONObject("branding"),
            )
        } catch (e: Exception) {
            Log.e(TAG, "parse failed: $e")
            null
        }

        private inline fun <T> parseList(
            arr: JSONArray?,
            parser: (JSONObject) -> T?,
        ): List<T> {
            if (arr == null) return emptyList()
            val out = mutableListOf<T>()
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                parser(item)?.let { out.add(it) }
            }
            return out
        }
    }
}

/** A sprite + its animation behavior. */
data class SpriteDef(
    val name: String,
    /** Folder path within filesDir/sprites/ (e.g. "v160_sprites/dragon_main"). */
    val manifestKey: String,
    val behavior: String,        // orbit | wander | translate | static
    val defaultFacing: String,   // "left" or "right"
    val params: JSONObject,
    val frameSkip: Int,          // framesPerTick for SpriteSheet
) {
    companion object {
        fun parse(j: JSONObject): SpriteDef? = try {
            SpriteDef(
                name = j.getString("name"),
                manifestKey = j.getString("manifest_key"),
                behavior = j.getString("behavior"),
                defaultFacing = j.optString("default_facing", "right"),
                params = j.optJSONObject("params") ?: JSONObject(),
                frameSkip = j.optInt("frame_skip", 2),
            )
        } catch (e: Exception) { null }
    }
}

/** A parallax image layer. URL points to the source on Supabase; the
 *  Dart side downloads it to filesDir/scene_layers/<scene_id>/<key>.webp
 *  before activating the wallpaper, where the renderer reads it. */
data class ImageLayerDef(
    val key: String,
    val url: String,
    val parallaxFactor: Float,   // gyro tilt depth (0=static, 1=full tilt)
    val scrollFactor: Float,     // home-page swipe pan (0=fixed, 1=full panoramic)
    val z: Int,
    /** Layer zoom relative to cover-fit. 1.0 = fill the surface (default).
     *  <1.0 shrinks the layer so it occupies LESS of the surface, leaving
     *  the layer(s) beneath it visible around the edges. Used to "step back"
     *  a foreground subject (e.g. Goku) without re-cropping the asset. */
    val scale: Float,
    /** Vertical sinusoidal bob. >0 makes the layer drift up/down forever
     *  (regardless of gyro/scroll input) — used for natural "floating"
     *  feel on subjects suspended in water/air. 0 = static (default). */
    val bobAmplitudePx: Float,
    /** Seconds per full bob cycle. Ignored when bobAmplitudePx == 0. */
    val bobPeriodSec: Float,
    /** When set, this layer's bob phase is derived from the target layer's
     *  key (not its own). Used to LOCK two layers' bobs in lockstep — e.g.
     *  a glow layer painted over a subject must drift IN PHASE with the
     *  subject, otherwise the glow visibly trails behind. Default: null
     *  → each layer gets its own phase shift via its own key hash. */
    val bobPhaseSource: String?,
    /** Initial alpha [0..1]. Default 1.0 (fully visible). Set 0.0 for layers
     *  that should be hidden until a collision triggers a rise_fade animation. */
    val initialAlpha: Float,
    /** Optional subject bbox normalized to TARGET (1080x2340). Used for
     *  collision detection. If null, the entire layer bitmap acts as bbox
     *  (rarely what you want — most layers are mostly transparent canvas). */
    val boundsNorm: android.graphics.RectF?,
    /** Autonomous motion (e.g. auto_jump every N seconds). Null = static. */
    val motion: MotionDef?,
    /** Collision-triggered animation. Each frame, the renderer checks if
     *  this layer's bounds intersect [collision.withLayer]'s bounds and,
     *  if so AND cooldown elapsed, triggers [collision.action]. */
    val collision: CollisionDef?,
) {
    companion object {
        fun parse(j: JSONObject): ImageLayerDef? = try {
            val pf = j.f("parallax_factor", 1f)
            ImageLayerDef(
                key = j.getString("key"),
                url = j.getString("url"),
                parallaxFactor = pf,
                // scroll_factor falls back to parallax_factor for backward compat,
                // BUT the typical usage is to set them independently:
                // a sky layer wants scroll=1.0 (panoramic) but parallax=0.05 (deep).
                scrollFactor = j.f("scroll_factor", pf),
                z = j.optInt("z", 0),
                scale = j.f("scale", 1f),
                bobAmplitudePx = j.f("bob_amplitude_px", 0f).coerceAtLeast(0f),
                bobPeriodSec = j.f("bob_period_sec", 4f).coerceAtLeast(0.1f),
                bobPhaseSource = j.optString("bob_phase_source").takeIf { it.isNotBlank() },
                initialAlpha = j.f("initial_alpha", 1f).coerceIn(0f, 1f),
                boundsNorm = parseRect(j.optJSONObject("bounds_norm")),
                motion = j.optJSONObject("motion")?.let { MotionDef.parse(it) },
                collision = j.optJSONObject("collision")?.let { CollisionDef.parse(it) },
            )
        } catch (e: Exception) { null }

        private fun parseRect(o: JSONObject?): android.graphics.RectF? {
            if (o == null) return null
            val x = o.f("x", -1f); val y = o.f("y", -1f)
            val w = o.f("w", -1f); val h = o.f("h", -1f)
            if (x < 0 || y < 0 || w <= 0 || h <= 0) return null
            return android.graphics.RectF(x, y, x + w, y + h)
        }
    }
}

/** Autonomous motion attached to an image_layer.
 *  Supported kinds:
 *    - "auto_jump"   — parabolic vertical arc every [intervalSec], peak at
 *      [amplitudePx] above resting position, lasts [durationSec].
 *    - "alpha_pulse" — alpha sinusoidally oscillates between [minAlpha] and
 *      [maxAlpha] with full period [periodSec]. Used for breathing glows
 *      (dragon eyes, embers, magic auras). */
data class MotionDef(
    val kind: String,
    val intervalSec: Float,
    val amplitudePx: Float,
    val durationSec: Float,
    val minAlpha: Float,
    val maxAlpha: Float,
    val periodSec: Float,
) {
    companion object {
        fun parse(j: JSONObject): MotionDef? = try {
            MotionDef(
                kind = j.optString("kind", "auto_jump"),
                intervalSec = j.f("interval_s", 4f).coerceAtLeast(0.5f),
                amplitudePx = j.f("amplitude_px", 200f).coerceAtLeast(10f),
                durationSec = j.f("duration_s", 0.8f).coerceAtLeast(0.1f),
                minAlpha = j.f("min_alpha", 0.3f).coerceIn(0f, 1f),
                maxAlpha = j.f("max_alpha", 1f).coerceIn(0f, 1f),
                periodSec = j.f("period_s", 1.5f).coerceAtLeast(0.1f),
            )
        } catch (e: Exception) { null }
    }
}

/** Frame cycle — time-multiplexes the alpha of N image_layers so exactly
 *  one is visible at any moment. Used for face blink (open / half / closed
 *  eye states), animated fire (frame_a/b/c), traffic lights, etc.
 *
 *  Frames are evaluated mod [durationSec]: at time t (modular), the frame
 *  whose [fromSec, toSec) window contains t becomes alpha=1, all other
 *  frames in this cycle go alpha=0.
 *
 *  Layers referenced by the cycle MUST exist in image_layers. Their
 *  declared initial_alpha is overridden every frame by the cycle. */
data class CycleDef(
    val name: String,
    val durationSec: Float,
    val frames: List<FrameDef>,
) {
    companion object {
        fun parse(j: JSONObject): CycleDef? {
            return try {
                val frames = mutableListOf<FrameDef>()
                val arr = j.optJSONArray("frames")
                if (arr != null) {
                    for (i in 0 until arr.length()) {
                        val item = arr.optJSONObject(i) ?: continue
                        FrameDef.parse(item)?.let { frames.add(it) }
                    }
                }
                if (frames.isEmpty()) null
                else CycleDef(
                    name = j.optString("name", "cycle"),
                    durationSec = j.f("duration_s", 4f).coerceAtLeast(0.1f),
                    frames = frames,
                )
            } catch (e: Exception) { null }
        }
    }
}

data class FrameDef(
    val layerKey: String,
    val fromSec: Float,
    val toSec: Float,
) {
    companion object {
        fun parse(j: JSONObject): FrameDef? = try {
            FrameDef(
                layerKey = j.getString("layer_key"),
                fromSec = j.f("from_s", 0f).coerceAtLeast(0f),
                toSec = j.f("to_s", 0f).coerceAtLeast(0f),
            )
        } catch (e: Exception) { null }
    }
}

/** Collision-driven action attached to an image_layer.
 *  Supported actions:
 *    - "bump_up"  — brief parabolic bump upward of [amplitudePx] over
 *      [durationSec]. Used for `?` blocks reacting to Mario's head.
 *    - "rise_fade" — slides up by [risePx] over [durationSec] while
 *      fading alpha 1→0. Used for coins/stars spawning from blocks.
 *      Layer should be defined with initial_alpha=0 so it's hidden at rest.
 *
 *  [cooldownSec] gates re-triggering. Default = 1.0s prevents Mario's
 *  return-down-through-block from triggering a second bump. */
data class CollisionDef(
    val withLayer: String,
    val action: String,
    val amplitudePx: Float,
    val risePx: Float,
    val durationSec: Float,
    val cooldownSec: Float,
) {
    companion object {
        fun parse(j: JSONObject): CollisionDef? = try {
            CollisionDef(
                withLayer = j.getString("with_layer"),
                action = j.optString("action", "bump_up"),
                amplitudePx = j.f("amplitude_px", 25f),
                risePx = j.f("rise_px", 200f),
                durationSec = j.f("duration_s", 0.4f).coerceAtLeast(0.05f),
                cooldownSec = j.f("cooldown_s", 1.0f).coerceAtLeast(0f),
            )
        } catch (e: Exception) { null }
    }
}

/** A particle system. */
data class ParticleDef(
    val kind: String,            // embers | motes | bubbles | snow | rain
    val params: JSONObject,
) {
    companion object {
        fun parse(j: JSONObject): ParticleDef? = try {
            ParticleDef(
                kind = j.getString("kind"),
                params = j.optJSONObject("params") ?: JSONObject(),
            )
        } catch (e: Exception) { null }
    }
}

/** A scheduled cinematic event. */
data class EventDef(
    val kind: String,            // phoenix | lightning_procedural | lightning_sprite | bat_swarm | flash_overlay
    /** Optional sprite name (for kinds that draw a sprite). */
    val sprite: String?,
    val intervalSec: Float,
    val durationSec: Float,
    val params: JSONObject,
) {
    companion object {
        fun parse(j: JSONObject): EventDef? = try {
            EventDef(
                kind = j.getString("kind"),
                sprite = j.optString("sprite").takeIf { it.isNotBlank() },
                intervalSec = j.optDouble("interval_s", 10.0).toFloat(),
                durationSec = j.optDouble("duration_s", 2.0).toFloat(),
                params = j.optJSONObject("params") ?: JSONObject(),
            )
        } catch (e: Exception) { null }
    }
}

/* ── Param helpers ──────────────────────────────────────────────────────
   JSON params can be ints or doubles; these tolerate both and coerce.
*/

fun JSONObject.f(key: String, default: Float = 0f): Float =
    if (has(key)) optDouble(key, default.toDouble()).toFloat() else default

fun JSONObject.i(key: String, default: Int = 0): Int =
    optInt(key, default)

fun JSONObject.b(key: String, default: Boolean = false): Boolean =
    optBoolean(key, default)

fun JSONObject.s(key: String, default: String = ""): String =
    optString(key, default)

/** Reads a param like "[0.5, 0.45]" into a Pair<Float,Float>. */
fun JSONObject.vec2(key: String, default: Pair<Float, Float>): Pair<Float, Float> {
    val arr = optJSONArray(key) ?: return default
    if (arr.length() < 2) return default
    return arr.optDouble(0).toFloat() to arr.optDouble(1).toFloat()
}

/** Reads a list of [x,y] pairs into List<Pair<Float,Float>>. */
fun JSONObject.vec2List(key: String): List<Pair<Float, Float>> {
    val arr = optJSONArray(key) ?: return emptyList()
    val out = mutableListOf<Pair<Float, Float>>()
    for (i in 0 until arr.length()) {
        val p = arr.optJSONArray(i) ?: continue
        if (p.length() >= 2) {
            out.add(p.optDouble(0).toFloat() to p.optDouble(1).toFloat())
        }
    }
    return out
}

/** Reads a list of color strings ("#RRGGBB" or "#AARRGGBB") into IntArray. */
fun JSONObject.colorList(key: String, fallback: IntArray): IntArray {
    val arr = optJSONArray(key) ?: return fallback
    val out = IntArray(arr.length())
    for (i in 0 until arr.length()) {
        val s = arr.optString(i)
        out[i] = try { Color.parseColor(s) } catch (_: Exception) { 0xFFFFFFFF.toInt() }
    }
    return if (out.isEmpty()) fallback else out
}
