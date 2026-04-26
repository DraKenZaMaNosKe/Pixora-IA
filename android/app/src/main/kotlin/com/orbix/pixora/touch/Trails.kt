package com.orbix.pixora.touch

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Shader
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.random.Random

/* ── Common helpers ──────────────────────────────────────────────────── */

private data class TouchPt(val x: Float, val y: Float, val time: Long)

private fun newPaint() = Paint(Paint.ANTI_ALIAS_FLAG)

/* ─────────────────────────────────────────────────────────────────────
   1. AURORA — flowing color-shifting ribbon through smoothed touch points
   ───────────────────────────────────────────────────────────────────── */
class AuroraTrail : TouchTrailRenderer {
    override val id = "aurora"
    override val displayName = "Aurora"
    private val points = mutableListOf<TouchPt>()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val maxAgeMs = 1500L
    override val isActive: Boolean get() = points.isNotEmpty()
    override fun onDown(x: Float, y: Float) { addPoint(x, y) }
    override fun onMove(x: Float, y: Float) { addPoint(x, y) }
    private fun addPoint(x: Float, y: Float) {
        points.add(TouchPt(x, y, System.currentTimeMillis()))
        if (points.size > 100) points.removeAt(0)
    }
    override fun reset() { points.clear() }
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, glowColor: Int) {
        val now = System.currentTimeMillis()
        // Drop ancient
        while (points.isNotEmpty() && now - points[0].time > maxAgeMs) points.removeAt(0)
        if (points.size < 2) return
        for (i in 1 until points.size) {
            val a = points[i - 1]
            val b = points[i]
            val ageRel = (now - b.time).toFloat() / maxAgeMs
            val alpha = (1f - ageRel).coerceIn(0f, 1f)
            if (alpha < 0.02f) continue
            // Color cycles through hues over time + index for shimmer
            val hue = (tick * 0.6f + i * 6f) % 360f
            paint.color = hslColor(hue, 0.85f, 0.65f, alpha * 0.85f)
            paint.strokeWidth = 14f * alpha + 2f
            canvas.drawLine(a.x, a.y, b.x, b.y, paint)
        }
    }
}

/* ─────────────────────────────────────────────────────────────────────
   2. SPARKS — magic firefly burst that flies outward + falls with gravity
   ───────────────────────────────────────────────────────────────────── */
class SparksTrail : TouchTrailRenderer {
    override val id = "sparks"
    override val displayName = "Sparks"
    private data class Spark(
        var x: Float, var y: Float, var vx: Float, var vy: Float,
        var life: Float, val maxLife: Float, val size: Float, val hue: Float,
    )
    private val sparks = mutableListOf<Spark>()
    private val paint = newPaint()
    override val isActive: Boolean get() = sparks.isNotEmpty()
    override fun onDown(x: Float, y: Float) { burst(x, y, 8) }
    override fun onMove(x: Float, y: Float) {
        if (Random.nextFloat() < 0.4f) burst(x, y, 1)
    }
    private fun burst(x: Float, y: Float, n: Int) {
        repeat(n) {
            val a = Random.nextFloat() * 6.28f
            val s = 30f + Random.nextFloat() * 80f
            sparks.add(Spark(
                x = x, y = y,
                vx = cos(a.toDouble()).toFloat() * s,
                vy = sin(a.toDouble()).toFloat() * s - 30f,
                life = 0f, maxLife = 0.6f + Random.nextFloat() * 0.6f,
                size = 1.5f + Random.nextFloat() * 2.5f,
                hue = 40f + Random.nextFloat() * 30f,
            ))
        }
    }
    override fun reset() { sparks.clear() }
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, glowColor: Int) {
        val dt = 1f / 60f // approximate 60fps
        val it = sparks.iterator()
        while (it.hasNext()) {
            val s = it.next()
            s.life += dt
            if (s.life > s.maxLife) { it.remove(); continue }
            s.x += s.vx * dt; s.y += s.vy * dt
            s.vy += 90f * dt
            val a = 1f - s.life / s.maxLife
            paint.color = hslColor(s.hue, 1f, 0.65f + a * 0.20f, a)
            canvas.drawCircle(s.x, s.y, s.size * a + 1f, paint)
        }
    }
}

/* ─────────────────────────────────────────────────────────────────────
   3. COMET — bright cosmic head + tapering blue tail
   ───────────────────────────────────────────────────────────────────── */
class CometTrail : TouchTrailRenderer {
    override val id = "comet"
    override val displayName = "Comet"
    private val points = mutableListOf<TouchPt>()
    private val maxAgeMs = 1200L
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND
    }
    override val isActive: Boolean get() = points.isNotEmpty()
    override fun onDown(x: Float, y: Float) { add(x, y) }
    override fun onMove(x: Float, y: Float) { add(x, y) }
    private fun add(x: Float, y: Float) {
        points.add(TouchPt(x, y, System.currentTimeMillis()))
        if (points.size > 60) points.removeAt(0)
    }
    override fun reset() { points.clear() }
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, glowColor: Int) {
        val now = System.currentTimeMillis()
        while (points.isNotEmpty() && now - points[0].time > maxAgeMs) points.removeAt(0)
        if (points.isEmpty()) return
        // Tail
        for (i in 1 until points.size) {
            val a = points[i - 1]; val b = points[i]
            val ageRel = (now - b.time).toFloat() / maxAgeMs
            val alpha = (1f - ageRel).coerceIn(0f, 1f)
            paint.color = Color.argb((alpha * 180).toInt().coerceIn(0, 255), 180, 220, 255)
            paint.strokeWidth = 8f * alpha + 1f
            canvas.drawLine(a.x, a.y, b.x, b.y, paint)
        }
        // Bright head
        val last = points.last()
        val ageRelHead = (now - last.time).toFloat() / 250f
        if (ageRelHead < 1f) {
            val a = (1f - ageRelHead).coerceIn(0f, 1f)
            val r = 18f * a + 8f
            paint.style = Paint.Style.FILL
            paint.shader = RadialGradient(last.x, last.y, r,
                Color.argb((255 * a).toInt(), 255, 255, 255),
                Color.argb(0, 156, 217, 255),
                Shader.TileMode.CLAMP)
            canvas.drawCircle(last.x, last.y, r, paint)
            paint.shader = null
            paint.style = Paint.Style.STROKE
        }
    }
}

/* ─────────────────────────────────────────────────────────────────────
   4. LIGHTNING — jagged electric line connecting recent touch points
   ───────────────────────────────────────────────────────────────────── */
class LightningTrail : TouchTrailRenderer {
    override val id = "lightning"
    override val displayName = "Lightning"
    private val points = mutableListOf<TouchPt>()
    private val maxAgeMs = 220L  // very brief — lightning is a flash
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val path = Path()
    override val isActive: Boolean get() = points.isNotEmpty()
    override fun onDown(x: Float, y: Float) { add(x, y) }
    override fun onMove(x: Float, y: Float) { add(x, y) }
    private fun add(x: Float, y: Float) {
        points.add(TouchPt(x, y, System.currentTimeMillis()))
        if (points.size > 12) points.removeAt(0)
    }
    override fun reset() { points.clear() }
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, glowColor: Int) {
        val now = System.currentTimeMillis()
        while (points.isNotEmpty() && now - points[0].time > maxAgeMs) points.removeAt(0)
        if (points.size < 2) return
        // Build jagged path through points
        path.reset()
        path.moveTo(points[0].x, points[0].y)
        for (i in 1 until points.size) {
            val a = points[i - 1]; val b = points[i]
            val segs = 4
            for (s in 1..segs) {
                val t = s / segs.toFloat()
                val px = a.x + (b.x - a.x) * t + (Random.nextFloat() - 0.5f) * 10f
                val py = a.y + (b.y - a.y) * t + (Random.nextFloat() - 0.5f) * 10f
                path.lineTo(px, py)
            }
        }
        val ageRel = (now - points.last().time).toFloat() / maxAgeMs
        val alpha = (1f - ageRel * 0.5f).coerceIn(0f, 1f)
        // Outer glow
        paint.color = Color.argb((alpha * 110).toInt(), 160, 220, 255)
        paint.strokeWidth = 8f
        canvas.drawPath(path, paint)
        // Bright core
        paint.color = Color.argb((alpha * 255).toInt(), 255, 255, 255)
        paint.strokeWidth = 2f
        canvas.drawPath(path, paint)
    }
}

/* ─────────────────────────────────────────────────────────────────────
   5. PETALS — sakura petals fall from touch points (zen)
   ───────────────────────────────────────────────────────────────────── */
class PetalsTrail : TouchTrailRenderer {
    override val id = "petals"
    override val displayName = "Petals"
    private data class Petal(
        var x: Float, var y: Float, var vx: Float, var vy: Float,
        var life: Float, val maxLife: Float, var angle: Float, val spin: Float,
        val size: Float, val hue: Float,
    )
    private val petals = mutableListOf<Petal>()
    private val paint = newPaint()
    override val isActive: Boolean get() = petals.isNotEmpty()
    override fun onDown(x: Float, y: Float) { spawn(x, y) }
    override fun onMove(x: Float, y: Float) { if (Random.nextFloat() < 0.35f) spawn(x, y) }
    private fun spawn(x: Float, y: Float) {
        petals.add(Petal(
            x = x, y = y,
            vx = (Random.nextFloat() - 0.5f) * 30f,
            vy = 10f + Random.nextFloat() * 20f,
            life = 0f, maxLife = 2.5f + Random.nextFloat(),
            angle = Random.nextFloat() * 6.28f,
            spin = (Random.nextFloat() - 0.5f) * 4f,
            size = 6f + Random.nextFloat() * 5f,
            hue = 340f + Random.nextFloat() * 25f,
        ))
    }
    override fun reset() { petals.clear() }
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, glowColor: Int) {
        val dt = 1f / 60f
        val timeF = tick.toFloat()
        val it = petals.iterator()
        while (it.hasNext()) {
            val p = it.next()
            p.life += dt
            if (p.life > p.maxLife) { it.remove(); continue }
            p.vy += 30f * dt
            p.vx += sin((timeF * 0.05 + p.angle).toDouble()).toFloat() * 12f * dt
            p.x += p.vx * dt; p.y += p.vy * dt
            p.angle += p.spin * dt
            val a = 1f - p.life / p.maxLife
            paint.color = hslColor(p.hue, 0.8f, 0.78f, a * 0.85f)
            canvas.save()
            canvas.translate(p.x, p.y)
            canvas.rotate(Math.toDegrees(p.angle.toDouble()).toFloat())
            // Petal = elongated ellipse
            canvas.drawOval(-p.size, -p.size * 0.55f, p.size, p.size * 0.55f, paint)
            canvas.restore()
        }
    }
}

/* ─────────────────────────────────────────────────────────────────────
   6. STARDUST — 4-pointed twinkling stars
   ───────────────────────────────────────────────────────────────────── */
class StardustTrail : TouchTrailRenderer {
    override val id = "stardust"
    override val displayName = "Stardust"
    private data class Star(
        var x: Float, var y: Float, var vx: Float, var vy: Float,
        var life: Float, val maxLife: Float, val size: Float, val twinklePhase: Float,
    )
    private val stars = mutableListOf<Star>()
    private val paint = newPaint().apply { style = Paint.Style.FILL }
    private val path = Path()
    override val isActive: Boolean get() = stars.isNotEmpty()
    override fun onDown(x: Float, y: Float) { spawn(x, y, 2) }
    override fun onMove(x: Float, y: Float) {
        if (Random.nextFloat() < 0.6f) spawn(x, y, 1)
    }
    private fun spawn(x: Float, y: Float, n: Int) {
        repeat(n) {
            stars.add(Star(
                x = x + (Random.nextFloat() - 0.5f) * 12f,
                y = y + (Random.nextFloat() - 0.5f) * 12f,
                vx = (Random.nextFloat() - 0.5f) * 12f,
                vy = (Random.nextFloat() - 0.7f) * 12f,
                life = 0f, maxLife = 1.2f + Random.nextFloat() * 0.8f,
                size = 4f + Random.nextFloat() * 4f,
                twinklePhase = Random.nextFloat() * 6.28f,
            ))
        }
    }
    override fun reset() { stars.clear() }
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, glowColor: Int) {
        val dt = 1f / 60f
        val it = stars.iterator()
        while (it.hasNext()) {
            val s = it.next()
            s.life += dt
            if (s.life > s.maxLife) { it.remove(); continue }
            s.x += s.vx * dt; s.y += s.vy * dt
            val ageA = 1f - s.life / s.maxLife
            val twinkle = 0.5f + 0.5f * sin((tick * 0.012f + s.twinklePhase).toDouble()).toFloat()
            val a = ageA * twinkle
            val r = s.size
            paint.color = Color.argb((a * 255).toInt().coerceIn(0, 255), 255, 245, 200)
            // 4-point star path
            path.reset()
            path.moveTo(s.x, s.y - r)
            path.lineTo(s.x + r * 0.3f, s.y - r * 0.3f)
            path.lineTo(s.x + r, s.y)
            path.lineTo(s.x + r * 0.3f, s.y + r * 0.3f)
            path.lineTo(s.x, s.y + r)
            path.lineTo(s.x - r * 0.3f, s.y + r * 0.3f)
            path.lineTo(s.x - r, s.y)
            path.lineTo(s.x - r * 0.3f, s.y - r * 0.3f)
            path.close()
            canvas.drawPath(path, paint)
        }
    }
}

/* ─────────────────────────────────────────────────────────────────────
   7. PIXORA GOLD — gold particles spiral around finger + brand halo
   ───────────────────────────────────────────────────────────────────── */
class PixoraGoldTrail : TouchTrailRenderer {
    override val id = "pixora_gold"
    override val displayName = "Pixora Gold"
    private data class GoldP(
        var x0: Float, var y0: Float,
        var angle: Float, val angleSpeed: Float,
        var radius: Float, val drift: Float,
        var life: Float, val maxLife: Float,
        val size: Float, val hue: Float,
    )
    private val particles = mutableListOf<GoldP>()
    private val paint = newPaint().apply { style = Paint.Style.FILL }
    private var lastTouchX = 0f
    private var lastTouchY = 0f
    private var lastTouchTime = 0L
    override val isActive: Boolean get() = particles.isNotEmpty() ||
        System.currentTimeMillis() - lastTouchTime < 200
    override fun onDown(x: Float, y: Float) { spawn(x, y); touch(x, y) }
    override fun onMove(x: Float, y: Float) {
        if (Random.nextFloat() < 0.5f) spawn(x, y)
        touch(x, y)
    }
    private fun touch(x: Float, y: Float) {
        lastTouchX = x; lastTouchY = y; lastTouchTime = System.currentTimeMillis()
    }
    private fun spawn(x: Float, y: Float) {
        particles.add(GoldP(
            x0 = x, y0 = y,
            angle = Random.nextFloat() * 6.28f,
            angleSpeed = (if (Random.nextBoolean()) 1f else -1f) * (3f + Random.nextFloat() * 3f),
            radius = 8f + Random.nextFloat() * 10f,
            drift = 25f + Random.nextFloat() * 20f,
            life = 0f, maxLife = 1.0f + Random.nextFloat() * 0.6f,
            size = 1.5f + Random.nextFloat() * 2f,
            hue = 40f + Random.nextFloat() * 12f,
        ))
    }
    override fun reset() { particles.clear() }
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, glowColor: Int) {
        val dt = 1f / 60f
        val now = System.currentTimeMillis()
        // Bright halo at last touch position (fades over 200ms after lift)
        val haloAge = (now - lastTouchTime).coerceAtMost(200L)
        if (haloAge < 200L) {
            val a = 1f - haloAge / 200f
            paint.shader = RadialGradient(lastTouchX, lastTouchY, 22f,
                Color.argb((255 * a * 0.85f).toInt(), 240, 221, 158),
                Color.argb(0, 201, 166, 80),
                Shader.TileMode.CLAMP)
            canvas.drawCircle(lastTouchX, lastTouchY, 22f, paint)
            paint.shader = null
        }
        val it = particles.iterator()
        while (it.hasNext()) {
            val p = it.next()
            p.life += dt
            if (p.life > p.maxLife) { it.remove(); continue }
            p.angle += p.angleSpeed * dt
            val a = 1f - p.life / p.maxLife
            val rNow = p.radius + p.life * p.drift
            val px = p.x0 + cos(p.angle.toDouble()).toFloat() * rNow
            val py = p.y0 + sin(p.angle.toDouble()).toFloat() * rNow - p.life * 15f
            paint.color = hslColor(p.hue, 0.8f, 0.65f + a * 0.15f, a)
            canvas.drawCircle(px, py, p.size * a + 0.5f, paint)
        }
    }
}

/* ── Color helper ────────────────────────────────────────────────────── */

/** HSL → ARGB color. h in [0,360], s,l,a in [0,1]. */
private fun hslColor(h: Float, s: Float, l: Float, a: Float): Int {
    val hh = (h % 360f + 360f) % 360f / 60f
    val c = (1f - kotlin.math.abs(2f * l - 1f)) * s
    val x = c * (1f - kotlin.math.abs(hh % 2f - 1f))
    val m = l - c / 2f
    val (rr, gg, bb) = when (hh.toInt()) {
        0 -> Triple(c, x, 0f)
        1 -> Triple(x, c, 0f)
        2 -> Triple(0f, c, x)
        3 -> Triple(0f, x, c)
        4 -> Triple(x, 0f, c)
        else -> Triple(c, 0f, x)
    }
    val r = ((rr + m) * 255f).toInt().coerceIn(0, 255)
    val g = ((gg + m) * 255f).toInt().coerceIn(0, 255)
    val b = ((bb + m) * 255f).toInt().coerceIn(0, 255)
    val ai = (a.coerceIn(0f, 1f) * 255f).toInt()
    return Color.argb(ai, r, g, b)
}
