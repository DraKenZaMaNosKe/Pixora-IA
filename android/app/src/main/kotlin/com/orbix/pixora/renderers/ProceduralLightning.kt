package com.orbix.pixora.renderers

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import kotlin.random.Random

/**
 * Code-drawn lightning bolt — replaces sprite-based lightning whose last
 * frames looked muddy. Three-strike envelope across a configurable
 * duration: initial strike, mid re-strike, late mini-strike, then fade.
 *
 * Usage:
 *   private val lightning = ProceduralLightning()
 *   if (shouldFire) lightning.start(tick, durationTicks=120, w, h)
 *   lightning.draw(canvas, tick)
 */
class ProceduralLightning {
    var active: Boolean = false
        private set

    private var startTick = 0L
    private var durationTicks = 120L
    private var surfaceW = 0
    private var surfaceH = 0
    private val path = Path()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val flashPaint = Paint()

    fun start(currentTick: Long, durationTicks: Long, surfaceWidth: Int, surfaceHeight: Int) {
        active = true
        startTick = currentTick
        this.durationTicks = durationTicks
        surfaceW = surfaceWidth
        surfaceH = surfaceHeight
        regenerate()
    }

    fun stop() { active = false }

    private fun regenerate() {
        path.reset()
        if (surfaceW <= 0) return
        val startX = surfaceW * (0.2f + Random.nextFloat() * 0.6f)
        val endX = startX + (Random.nextFloat() - 0.5f) * surfaceW * 0.3f
        val endY = surfaceH * (0.4f + Random.nextFloat() * 0.2f)
        val segs = 14
        path.moveTo(startX, 0f)
        var x = startX
        var y = 0f
        val dy = endY / segs
        val dx = (endX - startX) / segs
        for (i in 1..segs) {
            x += dx + (Random.nextFloat() - 0.5f) * surfaceW * 0.06f
            y += dy
            path.lineTo(x, y)
            if (Random.nextFloat() < 0.20f && i in 3..(segs - 2)) {
                val forkLen = surfaceH * (0.04f + Random.nextFloat() * 0.05f)
                val fx = x + (Random.nextFloat() - 0.5f) * surfaceW * 0.10f
                path.moveTo(x, y)
                path.lineTo(fx, y + forkLen)
                path.moveTo(x, y)
            }
        }
    }

    fun draw(canvas: Canvas, currentTick: Long) {
        if (!active) return
        val elapsed = (currentTick - startTick).toInt()
        val total = durationTicks.toInt()
        if (elapsed >= total) {
            active = false
            return
        }

        // Three-strike envelope: rise → hold → re-strike → fall → mini → fade
        val intensity: Float = when (elapsed) {
            in 0..4 -> elapsed / 5f
            in 5..16 -> 1f - (elapsed - 5) / 24f
            in 17..28 -> 0.5f - (elapsed - 17) / 33f
            in 29..31 -> { regenerate(); 1f }
            in 32..50 -> (1f - (elapsed - 32) / 18f).coerceAtLeast(0f)
            in 51..69 -> 0f
            in 70..72 -> { regenerate(); 0.75f }
            in 73..92 -> (0.75f * (1f - (elapsed - 73) / 19f)).coerceAtLeast(0f)
            else -> 0f
        }

        if (intensity <= 0.01f) return

        // Sky flash overlay
        flashPaint.color = Color.argb((50 * intensity).toInt().coerceIn(0, 255), 255, 255, 255)
        canvas.drawRect(0f, 0f, surfaceW.toFloat(), surfaceH.toFloat(), flashPaint)

        val alpha = (255 * intensity).toInt().coerceIn(0, 255)
        // Outer glow
        paint.strokeWidth = surfaceW * 0.018f
        paint.color = Color.argb((alpha * 0.25f).toInt().coerceIn(0, 255), 180, 210, 255)
        canvas.drawPath(path, paint)
        // Mid layer
        paint.strokeWidth = surfaceW * 0.008f
        paint.color = Color.argb((alpha * 0.7f).toInt().coerceIn(0, 255), 220, 230, 255)
        canvas.drawPath(path, paint)
        // Bright core
        paint.strokeWidth = surfaceW * 0.003f
        paint.color = Color.argb(alpha, 255, 255, 255)
        canvas.drawPath(path, paint)
    }
}
