package com.orbix.pixora.scene

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import com.orbix.pixora.renderers.ProceduralLightning
import com.orbix.pixora.renderers.SpriteSheet
import kotlin.random.Random

/**
 * Cinematic events that fire on a schedule. Each event owns its activation
 * state machine; CanvasSceneRenderer just calls draw() every frame and
 * the event decides whether it's currently visible.
 */
sealed class SceneEvent(val def: EventDef) {
    /** Sprite this event uses, or null if procedural. Looked up by name. */
    open val spriteName: String? get() = def.sprite

    /** ticks per interval (60 fps assumed). */
    val intervalTicks: Long get() = (def.intervalSec * 60f).toLong().coerceAtLeast(60L)
    val durationTicks: Long get() = (def.durationSec * 60f).toLong().coerceAtLeast(30L)

    abstract fun draw(
        canvas: Canvas,
        surfaceW: Int,
        surfaceH: Int,
        tick: Long,
        sprite: SpriteSheet?,
    )

    open fun reset() {}

    companion object {
        fun create(def: EventDef): SceneEvent? = when (def.kind) {
            "phoenix" -> PhoenixEvent(def)
            "lightning_procedural" -> LightningProceduralEvent(def)
            "lightning_sprite" -> LightningSpriteEvent(def)
            "bat_swarm" -> BatSwarmEvent(def)
            "flash_overlay" -> FlashOverlayEvent(def)
            else -> null
        }
    }
}

/* ── Phoenix (rises from bottom, scales + fades) ──────────────────────
   params: x, y_start, y_end
*/
class PhoenixEvent(def: EventDef) : SceneEvent(def) {
    private val x = def.params.f("x", 0.5f)
    private val yStart = def.params.f("y_start", 0.95f)
    private val yEnd = def.params.f("y_end", 0.20f)
    private val baseScale = def.params.f("scale", 0.0028f)

    private var active = false
    private var startTick = 0L

    override fun reset() { active = false }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, sprite: SpriteSheet?) {
        if (!active && tick > 0 && tick % intervalTicks == 0L) {
            active = true
            startTick = tick
            sprite?.reset()
        }
        if (!active || sprite == null) return
        sprite.advance()
        val elapsed = tick - startTick
        val t = (elapsed.toFloat() / durationTicks).coerceIn(0f, 1f)
        val y = surfaceH * (yStart - (yStart - yEnd) * t)
        val px = surfaceW * x
        val scaleProgress = if (t < 0.5f) t * 2f else 1f - (t - 0.5f) * 0.6f
        val scale = surfaceW * baseScale * scaleProgress
        val alpha = (255 * if (t < 0.1f) t / 0.1f
                          else if (t > 0.85f) (1 - (t - 0.85f) / 0.15f).coerceAtLeast(0f)
                          else 1f).toInt().coerceIn(0, 255)
        sprite.drawAt(canvas, px, y, scale = scale, alpha = alpha)
        if (elapsed >= durationTicks) active = false
    }
}

/* ── Procedural lightning (no sprite needed) ──────────────────────────
   params: (none — uses defaults from ProceduralLightning helper)
*/
class LightningProceduralEvent(def: EventDef) : SceneEvent(def) {
    private val proc = ProceduralLightning()
    override val spriteName: String? = null

    override fun reset() { proc.stop() }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, sprite: SpriteSheet?) {
        if (!proc.active && tick > 0 && tick % intervalTicks == 0L) {
            proc.start(tick, durationTicks, surfaceW, surfaceH)
        }
        proc.draw(canvas, tick)
    }
}

/* ── Sprite lightning (plays a sprite once at fixed position) ─────────
   params: x, y, scale
*/
class LightningSpriteEvent(def: EventDef) : SceneEvent(def) {
    private val x = def.params.f("x", 0.5f)
    private val y = def.params.f("y", 0.18f)
    private val baseScale = def.params.f("scale", 0.0024f)

    private var active = false
    private var startTick = 0L

    override fun reset() { active = false }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, sprite: SpriteSheet?) {
        if (!active && tick > 0 && tick % intervalTicks == 0L) {
            active = true
            startTick = tick
            sprite?.reset()
        }
        if (!active || sprite == null) return
        sprite.advance()
        val elapsed = tick - startTick
        val t = elapsed.toFloat() / durationTicks
        val alpha = (255 * if (t < 0.1f) t / 0.1f
                          else if (t > 0.7f) (1 - (t - 0.7f) / 0.3f).coerceAtLeast(0f)
                          else 1f).toInt().coerceIn(0, 255)
        sprite.drawAt(canvas, surfaceW * x, surfaceH * y,
            scale = surfaceW * baseScale, alpha = alpha)
        if (elapsed >= durationTicks) active = false
    }
}

/* ── Bat swarm (sprites fan out from origin) ──────────────────────────
   params: origin:[x,y], count, fan_angle_deg, speed
*/
class BatSwarmEvent(def: EventDef) : SceneEvent(def) {
    private val origin = def.params.vec2("origin", 0.5f to 0.32f)
    private val count = def.params.i("count", 5)
    private val baseSpeed = def.params.f("speed", 1.4f)
    private val baseScale = def.params.f("scale", 0.0008f)

    // Pre-generated random velocities (one per bat in the swarm)
    private val velocities = Array(count) {
        val angle = (Random.nextFloat() - 0.5f) * Math.PI.toFloat()
        floatArrayOf(kotlin.math.sin(angle), -kotlin.math.cos(angle.toDouble()).toFloat() * (0.6f + Random.nextFloat() * 0.6f))
    }

    private var active = false
    private var startTick = 0L

    override fun reset() { active = false }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, sprite: SpriteSheet?) {
        if (!active && tick > 0 && tick % intervalTicks == 0L) {
            active = true
            startTick = tick
        }
        if (!active || sprite == null) return
        sprite.advance()
        val elapsed = (tick - startTick).toFloat()
        val t = elapsed / durationTicks
        val originX = surfaceW * origin.first
        val originY = surfaceH * origin.second
        for ((i, v) in velocities.withIndex()) {
            val baseTick = elapsed - i * 12f
            if (baseTick < 0f) continue
            val px = originX + v[0] * baseTick * baseSpeed
            val py = originY + v[1] * baseTick * baseSpeed
            val alpha = (255 * (1f - t).coerceIn(0f, 1f)).toInt()
            sprite.drawAt(canvas, px, py,
                scale = surfaceW * baseScale,
                flipX = v[0] > 0, alpha = alpha)
        }
        if (elapsed >= durationTicks) active = false
    }
}

/* ── Flash overlay (full-screen color flash, fades) ───────────────────
   params: color (#RRGGBB), peak_alpha (0..255), fade_s
*/
class FlashOverlayEvent(def: EventDef) : SceneEvent(def) {
    private val color = try { Color.parseColor(def.params.s("color", "#FFFFFF")) }
        catch (_: Exception) { Color.WHITE }
    private val peakAlpha = def.params.i("peak_alpha", 60)
    private val paint = Paint()
    private var active = false
    private var startTick = 0L
    override val spriteName: String? = null

    override fun reset() { active = false }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, sprite: SpriteSheet?) {
        if (!active && tick > 0 && tick % intervalTicks == 0L) {
            active = true
            startTick = tick
        }
        if (!active) return
        val elapsed = tick - startTick
        val t = elapsed.toFloat() / durationTicks
        val a = (peakAlpha * (1f - t).coerceIn(0f, 1f)).toInt()
        if (a > 0) {
            paint.color = Color.argb(a, Color.red(color), Color.green(color), Color.blue(color))
            canvas.drawRect(0f, 0f, surfaceW.toFloat(), surfaceH.toFloat(), paint)
        }
        if (elapsed >= durationTicks) active = false
    }
}
