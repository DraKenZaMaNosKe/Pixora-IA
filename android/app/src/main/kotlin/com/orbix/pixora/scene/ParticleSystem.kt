package com.orbix.pixora.scene

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * Per-frame particle simulation. New kinds are added by subclassing and
 * registering in CanvasSceneRenderer.
 */
sealed class ParticleSystem(val def: ParticleDef) {
    abstract fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long)
    open fun reset() {}

    companion object {
        fun create(def: ParticleDef): ParticleSystem? = when (def.kind) {
            "embers" -> EmberSystem(def)
            "motes" -> MoteSystem(def)
            "bubbles" -> BubbleSystem(def)
            "snow" -> SnowSystem(def)
            "rain" -> RainSystem(def)
            "wisps" -> WispSystem(def)
            else -> null
        }
    }
}

/* ── Embers (rising hot particles) ─────────────────────────────────────
   params: spawn_x, spawn_y, spread_x, spread_y_jitter_px, count, speed,
           angular_spread, colors:[#hex,...]
*/
class EmberSystem(def: ParticleDef) : ParticleSystem(def) {
    private val spawnX = def.params.f("spawn_x", 0.5f)
    private val spawnY = def.params.f("spawn_y", 0.45f)
    private val spreadX = def.params.f("spread_x", 0.06f)
    private val spreadYJitterPx = def.params.f("spread_y_jitter_px", 18f)
    private val count = def.params.i("count", 36)
    private val speed = def.params.f("speed", 1.8f)
    private val angularSpread = def.params.f("angular_spread", 0.6f)
    private val colors = def.params.colorList("colors",
        intArrayOf(0xFFFFB040.toInt(), 0xFFFF8820.toInt(),
            0xFFFFCC60.toInt(), 0xFFFF6A10.toInt()))

    private data class Ember(
        var x: Float, var y: Float,
        var vx: Float, var vy: Float,
        var radius: Float,
        var life: Float, var maxLife: Float,
        val color: Int,
    )

    private val embers = mutableListOf<Ember>()
    private var initialized = false
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    override fun reset() { embers.clear(); initialized = false }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        if (!initialized) { spawn(surfaceW, surfaceH, count); initialized = true }

        val it = embers.iterator()
        while (it.hasNext()) {
            val e = it.next()
            e.x += e.vx
            e.y += e.vy
            e.vy *= 0.994f
            e.life -= 0.012f
            if (e.life <= 0f || e.y < -20f) { it.remove(); continue }
            val a = ((e.life / e.maxLife) * 255).toInt().coerceIn(0, 255)
            paint.color = Color.argb(a, Color.red(e.color), Color.green(e.color), Color.blue(e.color))
            canvas.drawCircle(e.x, e.y, e.radius, paint)
        }
        while (embers.size < count) spawn(surfaceW, surfaceH, 1)
    }

    private fun spawn(surfaceW: Int, surfaceH: Int, n: Int) {
        val cx = surfaceW * spawnX
        val cy = surfaceH * spawnY
        repeat(n) {
            val angle = Random.nextFloat() * angularSpread - angularSpread / 2f
            val sp = Random.nextFloat() * 1.4f + speed * 0.55f
            val life = Random.nextFloat() * 0.7f + 0.6f
            embers.add(Ember(
                x = cx + (Random.nextFloat() - 0.5f) * surfaceW * spreadX,
                y = cy + (Random.nextFloat() - 0.5f) * spreadYJitterPx,
                vx = sin(angle.toDouble()).toFloat() * sp * 0.25f,
                vy = -sp * (speed * 0.55f + 0.7f),
                radius = Random.nextFloat() * 2.2f + 1.4f,
                life = life, maxLife = life,
                color = colors[Random.nextInt(colors.size)],
            ))
        }
    }
}

/* ── Motes (slow-rising specks) ────────────────────────────────────────
   params: count, drift, vy, color, color_alpha_max
*/
class MoteSystem(def: ParticleDef) : ParticleSystem(def) {
    private val count = def.params.i("count", 28)
    private val drift = def.params.f("drift", 0.4f)
    private val vyMin = def.params.f("vy_min", -0.75f)
    private val vyMax = def.params.f("vy_max", -0.25f)
    private val color = try { Color.parseColor(def.params.s("color", "#DCB478")) }
        catch (_: Exception) { 0xFFDCB478.toInt() }
    private val maxAlpha = def.params.i("max_alpha", 200)

    private data class Mote(
        var x: Float, var y: Float,
        var vy: Float, var phaseOffset: Float, var amp: Float,
        var radius: Float, var life: Float, var maxLife: Float,
    )

    private val motes = mutableListOf<Mote>()
    private var initialized = false
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    override fun reset() { motes.clear(); initialized = false }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        if (!initialized) { spawn(surfaceW, surfaceH, count); initialized = true }

        val it = motes.iterator()
        while (it.hasNext()) {
            val m = it.next()
            m.phaseOffset += 0.04f
            m.x += sin(m.phaseOffset.toDouble()).toFloat() * m.amp
            m.y += m.vy
            m.life -= 0.006f
            if (m.life <= 0f || m.y < -10f) { it.remove(); continue }
            val a = ((m.life / m.maxLife) * maxAlpha).toInt().coerceIn(0, 255)
            paint.color = Color.argb(a, Color.red(color), Color.green(color), Color.blue(color))
            canvas.drawCircle(m.x, m.y, m.radius, paint)
        }
        while (motes.size < count) spawn(surfaceW, surfaceH, 1)
    }

    private fun spawn(surfaceW: Int, surfaceH: Int, n: Int) {
        repeat(n) {
            val life = Random.nextFloat() * 0.5f + 0.7f
            motes.add(Mote(
                x = Random.nextFloat() * surfaceW,
                y = surfaceH * (0.82f + Random.nextFloat() * 0.18f),
                vy = vyMin + Random.nextFloat() * (vyMax - vyMin),
                phaseOffset = Random.nextFloat() * 6.28f,
                amp = Random.nextFloat() * drift + drift * 0.4f,
                radius = Random.nextFloat() * 1.6f + 0.8f,
                life = life, maxLife = life,
            ))
        }
    }
}

/* ── Stubs for v1.7 schema completeness ───────────────────────────────
   These render nothing yet — implementations land when the first
   wallpaper that needs them ships. The CapabilityRegistry already
   declares them as supported so future wallpapers will load even on
   today's clients.
*/

class BubbleSystem(def: ParticleDef) : ParticleSystem(def) {
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {}
}

class SnowSystem(def: ParticleDef) : ParticleSystem(def) {
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {}
}

class RainSystem(def: ParticleDef) : ParticleSystem(def) {
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {}
}

/* ── Wisps (fixed-position glowing orbs with subtle wobble) ──────────
   For valley fog, mystic lights, lantern halos. Each anchor renders as
   a soft RadialGradient halo + bright core.

   params: anchors:[[x,y],...], color (#hex), radius, wobble_amplitude
*/
class WispSystem(def: ParticleDef) : ParticleSystem(def) {
    private val anchors = def.params.vec2List("anchors")
    private val color = try { Color.parseColor(def.params.s("color", "#FFC8E6FF")) }
        catch (_: Exception) { 0xFFC8E6FF.toInt() }
    private val radiusFrac = def.params.f("radius", 0.018f)
    private val wobbleAmp = def.params.f("wobble_amplitude", 8f)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        if (anchors.isEmpty()) return
        for ((i, w) in anchors.withIndex()) {
            val phase = tick * 0.04f + i * 1.3f
            val intensity = 0.6f + 0.4f * sin(phase.toDouble()).toFloat()
            val cx = surfaceW * w.first + sin((phase * 0.7).toDouble()).toFloat() * wobbleAmp
            val cy = surfaceH * w.second + cos((phase * 0.5).toDouble()).toFloat() * wobbleAmp * 0.75f
            val rOuter = surfaceW * radiusFrac
            // Halo
            paint.shader = RadialGradient(
                cx, cy, rOuter,
                Color.argb((220 * intensity).toInt().coerceIn(0, 255),
                    Color.red(color), Color.green(color), Color.blue(color)),
                Color.argb(0, Color.red(color), Color.green(color), Color.blue(color)),
                Shader.TileMode.CLAMP,
            )
            canvas.drawCircle(cx, cy, rOuter, paint)
            paint.shader = null
            // Bright core
            paint.color = Color.argb((255 * intensity).toInt().coerceIn(0, 255), 240, 250, 255)
            canvas.drawCircle(cx, cy, surfaceW * 0.005f, paint)
        }
    }
}
