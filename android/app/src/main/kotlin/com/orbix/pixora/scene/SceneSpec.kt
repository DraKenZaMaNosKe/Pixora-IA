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
