package com.orbix.pixora.scene

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
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
            "glass_drops" -> GlassDropsSystem(def)
            "fireflies" -> FireflySystem(def)
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

/* ── Rain (diagonal falling streaks) ──────────────────────────────────
   3 parallax tiers: near (bright, fast, big), mid, far (dim, slow, blurred).
   Each drop is a short tapered line with head + tail.

   params:
     count        total drops (split evenly across tiers, default 90)
     angle_deg    tilt off vertical (default 12)
     speed        base fall speed multiplier (default 1.0)
     length_px    base streak length in px (default 18)
     color        "#RRGGBB" or "#AARRGGBB" (default "#E6F0FF")
     near_alpha   alpha of foreground tier (default 0.85)
*/
class RainSystem(def: ParticleDef) : ParticleSystem(def) {
    private val totalCount = def.params.i("count", 90)
    private val angleRad = Math.toRadians(def.params.f("angle_deg", 12f).toDouble()).toFloat()
    private val speedMul = def.params.f("speed", 1.0f)
    private val baseLen = def.params.f("length_px", 18f)
    private val color = try { Color.parseColor(def.params.s("color", "#FFE6F0FF")) }
        catch (_: Exception) { 0xFFE6F0FF.toInt() }
    private val nearAlpha = def.params.f("near_alpha", 0.85f)

    private data class Drop(
        var x: Float, var y: Float,
        val speed: Float, val len: Float,
        val width: Float, val alpha: Float,
    )

    private val drops = mutableListOf<Drop>()
    private var initialized = false
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    // Pre-computed motion vector
    private val dx = sin(angleRad)
    private val dy = cos(angleRad)
    // Offscreen pad so drops can spawn outside the visible rect
    private val pad = 80f

    override fun reset() { drops.clear(); initialized = false }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        if (!initialized) { spawn(surfaceW, surfaceH); initialized = true }
        val w = surfaceW.toFloat(); val h = surfaceH.toFloat()
        for (d in drops) {
            d.x += dx * d.speed
            d.y += dy * d.speed
            // Wrap when off bottom or sides
            if (d.y > h + pad || d.x < -pad * 1.5f || d.x > w + pad * 1.5f) {
                d.y = -pad - Random.nextFloat() * 60f
                d.x = -pad + Random.nextFloat() * (w + pad * 2f)
            }
            // Streak as tapered line: start = current, end = behind by len
            val x2 = d.x - dx * d.len
            val y2 = d.y - dy * d.len
            paint.color = Color.argb((d.alpha * 255).toInt().coerceIn(0, 255),
                Color.red(color), Color.green(color), Color.blue(color))
            paint.strokeWidth = d.width
            canvas.drawLine(d.x, d.y, x2, y2, paint)
        }
    }

    private fun spawn(surfaceW: Int, surfaceH: Int) {
        val w = surfaceW.toFloat(); val h = surfaceH.toFloat()
        // Tier weights: near 30%, mid 40%, far 30%
        val nearN = (totalCount * 0.30f).toInt()
        val midN = (totalCount * 0.40f).toInt()
        val farN = totalCount - nearN - midN
        // Near
        repeat(nearN) {
            drops.add(Drop(
                x = -pad + Random.nextFloat() * (w + pad * 2f),
                y = -pad + Random.nextFloat() * (h + pad * 2f),
                speed = (24f + Random.nextFloat() * 14f) * speedMul,
                len = baseLen * (1.1f + Random.nextFloat() * 0.4f),
                width = 2.0f,
                alpha = nearAlpha * (0.9f + Random.nextFloat() * 0.1f),
            ))
        }
        // Mid
        repeat(midN) {
            drops.add(Drop(
                x = -pad + Random.nextFloat() * (w + pad * 2f),
                y = -pad + Random.nextFloat() * (h + pad * 2f),
                speed = (16f + Random.nextFloat() * 10f) * speedMul,
                len = baseLen * (0.8f + Random.nextFloat() * 0.3f),
                width = 1.4f,
                alpha = nearAlpha * 0.65f,
            ))
        }
        // Far
        repeat(farN) {
            drops.add(Drop(
                x = -pad + Random.nextFloat() * (w + pad * 2f),
                y = -pad + Random.nextFloat() * (h + pad * 2f),
                speed = (8f + Random.nextFloat() * 6f) * speedMul,
                len = baseLen * (0.5f + Random.nextFloat() * 0.3f),
                width = 1.0f,
                alpha = nearAlpha * 0.35f,
            ))
        }
    }
}

/* ── Stubs for v1.7 schema completeness ───────────────────────────────
   The CapabilityRegistry declares them as supported so future
   wallpapers using these will load even on today's clients.
*/

class BubbleSystem(def: ParticleDef) : ParticleSystem(def) {
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {}
}

class SnowSystem(def: ParticleDef) : ParticleSystem(def) {
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

/* ── Glass drops (water droplets sliding down the screen surface) ─────
   Realistic "rain on a window" effect. Each drop appears at the upper
   portion, sits motionless for a moment, then slides down accelerating
   under gravity, leaving a thin wet trail behind.

   params:
     count          number of drops at any time (default 12)
     size_min_px    smallest drop radius (default 5)
     size_max_px    biggest drop radius (default 14)
     color          "#AARRGGBB" — drop tint, default semi-transparent white
     spawn_top      normalized y top edge of spawn band (default 0.0)
     spawn_bottom   normalized y bottom edge of spawn band (default 0.4)
     fall_speed     base gravity multiplier (default 1.0)
     trail          show wet trail behind sliding drops (default true)
     wobble_px      horizontal wobble amplitude during slide (default 0.6)
     sit_min_s      min seconds drop sits before sliding (default 0.5)
     sit_max_s      max seconds drop sits before sliding (default 2.0)
*/
class GlassDropsSystem(def: ParticleDef) : ParticleSystem(def) {
    private val count = def.params.i("count", 12)
    private val sizeMin = def.params.f("size_min_px", 5f)
    private val sizeMax = def.params.f("size_max_px", 14f)
    private val color = try { Color.parseColor(def.params.s("color", "#FFFFFFFF")) }
        catch (_: Exception) { Color.WHITE }
    private val spawnTop = def.params.f("spawn_top", 0f)
    private val spawnBottom = def.params.f("spawn_bottom", 0.4f)
    private val fallSpeed = def.params.f("fall_speed", 1f)
    private val trail = def.params.b("trail", true)
    private val wobblePx = def.params.f("wobble_px", 0.6f)
    private val sitMinFrames = (def.params.f("sit_min_s", 0.5f) * 60f).toInt()
    private val sitMaxFrames = (def.params.f("sit_max_s", 2.0f) * 60f).toInt()

    private data class Drop(
        var x: Float, var y: Float,
        var vy: Float,
        var radius: Float,
        var spawnY: Float,        // start of trail
        var sittingFrames: Int,   // remaining frames before slide begins
        var phase: Float,         // wobble accumulator
    )

    private val drops = mutableListOf<Drop>()
    private var initialized = false
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val cR = Color.red(color)
    private val cG = Color.green(color)
    private val cB = Color.blue(color)

    override fun reset() { drops.clear(); initialized = false }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        if (!initialized) { spawn(surfaceW, surfaceH); initialized = true }
        val w = surfaceW.toFloat(); val h = surfaceH.toFloat()

        for (d in drops) {
            d.phase += 0.03f

            if (d.sittingFrames > 0) {
                d.sittingFrames--
            } else {
                // Surface tension overcome — gravity kicks in (acceleration)
                d.vy += 0.25f * fallSpeed
                d.y += d.vy
                if (wobblePx > 0f) {
                    d.x += sin(d.phase.toDouble()).toFloat() * wobblePx
                }
            }

            // Off bottom → respawn at top with new size
            if (d.y - d.radius > h) {
                respawn(d, w, h)
                continue
            }

            // 1. Wet trail (drawn first so the drop sits on top)
            if (trail && d.y > d.spawnY + 4f) {
                paint.shader = LinearGradient(
                    d.x, d.spawnY, d.x, d.y,
                    Color.argb(0, cR, cG, cB),
                    Color.argb(70, cR, cG, cB),
                    Shader.TileMode.CLAMP,
                )
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = d.radius * 0.45f
                canvas.drawLine(d.x, d.spawnY, d.x, d.y, paint)
                paint.shader = null
                paint.style = Paint.Style.FILL
            }

            // 2. Drop body — three layered circles for "water lens" depth
            // Outer dark rim (refraction edge)
            paint.color = Color.argb(75, 15, 25, 40)
            canvas.drawCircle(d.x, d.y, d.radius * 1.10f, paint)
            // Main lens body (semi-transparent water tint)
            paint.color = Color.argb(150, cR, cG, cB)
            canvas.drawCircle(d.x, d.y, d.radius, paint)
            // Bright highlight at upper-left (specular)
            paint.color = Color.argb(220, 255, 255, 255)
            canvas.drawCircle(
                d.x - d.radius * 0.32f,
                d.y - d.radius * 0.32f,
                d.radius * 0.28f,
                paint,
            )
        }
    }

    private fun respawn(d: Drop, w: Float, h: Float) {
        d.x = Random.nextFloat() * w
        val newY = -d.radius * 2f
        d.y = newY
        d.spawnY = newY
        d.vy = 0f
        d.radius = sizeMin + Random.nextFloat() * (sizeMax - sizeMin)
        d.sittingFrames = sitMinFrames + Random.nextInt((sitMaxFrames - sitMinFrames).coerceAtLeast(1))
    }

    private fun spawn(surfaceW: Int, surfaceH: Int) {
        val w = surfaceW.toFloat(); val h = surfaceH.toFloat()
        repeat(count) {
            val r = sizeMin + Random.nextFloat() * (sizeMax - sizeMin)
            val y = h * (spawnTop + Random.nextFloat() * (spawnBottom - spawnTop))
            drops.add(Drop(
                x = Random.nextFloat() * w,
                y = y, vy = 0f, radius = r, spawnY = y,
                sittingFrames = sitMinFrames + Random.nextInt(
                    (sitMaxFrames - sitMinFrames).coerceAtLeast(1)),
                phase = Random.nextFloat() * 6.28f,
            ))
        }
    }
}

/* ── Fireflies (glowing pulsing particles drifting upward) ────────────
   Each firefly = bright core + soft radial halo, pulses in alpha,
   drifts horizontally while rising slowly. Respawns at the bottom
   when it goes off the top.

   params:
     count         number of fireflies (default 18)
     size_min_px   smallest core radius (default 2.5)
     size_max_px   biggest core radius (default 4.5)
     halo_mul      halo radius = core * halo_mul (default 5)
     color         "#AARRGGBB" — body tint (default warm yellow)
     pulse_speed   how fast they blink (default 0.04, slower = slower pulse)
     drift_amp     horizontal sine drift in px (default 0.6)
     vy_min/max    upward velocity range (negative = up, default -0.4 to -0.1)
     spawn_top     normalized y top of spawn band (default 0.4)
     spawn_bottom  normalized y bottom of spawn band (default 1.0)
*/
class FireflySystem(def: ParticleDef) : ParticleSystem(def) {
    private val count = def.params.i("count", 18)
    private val sizeMin = def.params.f("size_min_px", 2.5f)
    private val sizeMax = def.params.f("size_max_px", 4.5f)
    private val haloMul = def.params.f("halo_mul", 5f)
    private val color = try { Color.parseColor(def.params.s("color", "#FFFFE082")) }
        catch (_: Exception) { 0xFFFFE082.toInt() }
    private val pulseSpeed = def.params.f("pulse_speed", 0.04f)
    private val driftAmp = def.params.f("drift_amp", 0.6f)
    private val vyMin = def.params.f("vy_min", -0.4f)
    private val vyMax = def.params.f("vy_max", -0.1f)
    private val spawnTop = def.params.f("spawn_top", 0.4f)
    private val spawnBottom = def.params.f("spawn_bottom", 1.0f)

    private data class Firefly(
        var x: Float, var y: Float,
        var vy: Float, var driftPhase: Float, var pulsePhase: Float,
        var radius: Float,
    )

    private val flies = mutableListOf<Firefly>()
    private var initialized = false
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val cR = Color.red(color)
    private val cG = Color.green(color)
    private val cB = Color.blue(color)

    override fun reset() { flies.clear(); initialized = false }

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        if (!initialized) { spawn(surfaceW, surfaceH); initialized = true }
        val w = surfaceW.toFloat(); val h = surfaceH.toFloat()
        for (f in flies) {
            f.driftPhase += 0.04f
            f.pulsePhase += pulseSpeed
            f.x += sin(f.driftPhase.toDouble()).toFloat() * driftAmp
            f.y += f.vy
            if (f.y < -20f || f.x < -20f || f.x > w + 20f) {
                respawn(f, w, h)
            }
            // Pulse intensity 0.25 .. 1.0 (never goes fully dark — fireflies are visible even at min)
            val pulse = 0.25f + 0.75f * (0.5f + 0.5f * sin(f.pulsePhase.toDouble()).toFloat())
            // Soft halo
            val haloR = f.radius * haloMul
            paint.shader = RadialGradient(
                f.x, f.y, haloR,
                Color.argb((180 * pulse).toInt().coerceIn(0, 255), cR, cG, cB),
                Color.argb(0, cR, cG, cB),
                Shader.TileMode.CLAMP,
            )
            canvas.drawCircle(f.x, f.y, haloR, paint)
            paint.shader = null
            // Bright white-ish core (always luminous)
            paint.color = Color.argb((255 * pulse).toInt().coerceIn(0, 255), 255, 250, 220)
            canvas.drawCircle(f.x, f.y, f.radius, paint)
        }
    }

    private fun respawn(f: Firefly, w: Float, h: Float) {
        f.x = Random.nextFloat() * w
        f.y = h * (spawnTop + Random.nextFloat() * (spawnBottom - spawnTop))
        f.vy = vyMin + Random.nextFloat() * (vyMax - vyMin)
        f.radius = sizeMin + Random.nextFloat() * (sizeMax - sizeMin)
    }

    private fun spawn(surfaceW: Int, surfaceH: Int) {
        val w = surfaceW.toFloat(); val h = surfaceH.toFloat()
        repeat(count) {
            val r = sizeMin + Random.nextFloat() * (sizeMax - sizeMin)
            flies.add(Firefly(
                x = Random.nextFloat() * w,
                y = h * (spawnTop + Random.nextFloat() * (spawnBottom - spawnTop)),
                vy = vyMin + Random.nextFloat() * (vyMax - vyMin),
                driftPhase = Random.nextFloat() * 6.28f,
                pulsePhase = Random.nextFloat() * 6.28f,
                radius = r,
            ))
        }
    }
}
