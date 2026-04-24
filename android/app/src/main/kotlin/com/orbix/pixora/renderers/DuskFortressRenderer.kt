package com.orbix.pixora.renderers

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kotlin.math.sin
import kotlin.random.Random

/**
 * Pure-particle renderer for Pixora Dusk Fortress wallpaper.
 * No sprites required — torches flicker in the castle windows and
 * ash/ember particles drift gently upward from the valley mist.
 */
class DuskFortressRenderer {

    var surfaceWidth = 0
    var surfaceHeight = 0

    private val motes = mutableListOf<Mote>()
    private var initialized = false
    private var flickerPhase = 0f

    private val motePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val torchPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private data class Mote(
        var x: Float,
        var y: Float,
        var vy: Float,
        var drift: Float,
        var phase: Float,
        var radius: Float,
        var life: Float,
        var maxLife: Float,
    )

    /**
     * Torch positions as fractions of (surfaceWidth, surfaceHeight).
     * Calibrated to the Gemini source — castle spans ~40-70% X and
     * ~35-60% Y with arrow-slit windows scattered among towers.
     */
    private val torchSpots = arrayOf(
        floatArrayOf(0.50f, 0.44f), // central tower low window
        floatArrayOf(0.54f, 0.38f), // central tower mid window
        floatArrayOf(0.47f, 0.41f), // left tower upper
        floatArrayOf(0.58f, 0.48f), // right tower lower
        floatArrayOf(0.52f, 0.33f), // tallest tower top
    )

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        if (!initialized) {
            spawn(28)
            initialized = true
        }

        // Flickering torch lights — each has its own phase offset so they
        // don't pulse in sync.
        flickerPhase += 0.18f
        for ((i, spot) in torchSpots.withIndex()) {
            val phase = flickerPhase + i * 1.17f
            val intensity = 0.65f + 0.35f * sin(phase.toDouble()).toFloat()
            val alpha = (intensity * 200).toInt().coerceIn(0, 220)
            val cx = surfaceWidth * spot[0]
            val cy = surfaceHeight * spot[1]
            // outer warm glow
            torchPaint.color = Color.argb((alpha * 0.35).toInt(), 255, 150, 60)
            canvas.drawCircle(cx, cy, surfaceWidth * 0.018f, torchPaint)
            // middle
            torchPaint.color = Color.argb((alpha * 0.6).toInt(), 255, 180, 90)
            canvas.drawCircle(cx, cy, surfaceWidth * 0.010f, torchPaint)
            // bright core
            torchPaint.color = Color.argb(alpha, 255, 220, 140)
            canvas.drawCircle(cx, cy, surfaceWidth * 0.005f, torchPaint)
        }

        // Ash / ember motes drifting upward from the valley
        val iter = motes.iterator()
        while (iter.hasNext()) {
            val m = iter.next()
            m.phase += 0.04f
            m.x += sin(m.phase.toDouble()).toFloat() * m.drift
            m.y += m.vy
            m.life -= 0.006f
            if (m.life <= 0f || m.y < -10f) {
                iter.remove()
                continue
            }
            val alpha = ((m.life / m.maxLife) * 180).toInt().coerceIn(0, 200)
            motePaint.color = Color.argb(alpha, 220, 180, 120)
            canvas.drawCircle(m.x, m.y, m.radius, motePaint)
        }
        while (motes.size < 28) spawn(1)
    }

    private fun spawn(n: Int) {
        repeat(n) {
            val life = Random.nextFloat() * 0.5f + 0.7f
            motes.add(
                Mote(
                    x = Random.nextFloat() * surfaceWidth,
                    y = surfaceHeight * (0.82f + Random.nextFloat() * 0.18f),
                    vy = -(Random.nextFloat() * 0.5f + 0.25f),
                    drift = Random.nextFloat() * 0.4f + 0.15f,
                    phase = Random.nextFloat() * 6.28f,
                    radius = Random.nextFloat() * 1.6f + 0.8f,
                    life = life,
                    maxLife = life,
                )
            )
        }
    }

    fun reset() {
        motes.clear()
        initialized = false
        flickerPhase = 0f
    }
}
