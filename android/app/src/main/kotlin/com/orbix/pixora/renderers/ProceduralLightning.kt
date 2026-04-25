package com.orbix.pixora.renderers

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * Code-drawn lightning bolt — replaces sprite-based lightning whose last
 * frames looked muddy. Three-strike envelope across a configurable
 * duration: initial strike, mid re-strike, late mini-strike, then fade.
 *
 * Each strike is built as a collection of Segments (line + width factor),
 * not a single Path, so tips actually taper. Main bolt forks recursively
 * (depth 2) with a sideways bias to mimic natural lightning branching.
 */
class ProceduralLightning {
    var active: Boolean = false
        private set

    private var startTick = 0L
    private var durationTicks = 120L
    private var surfaceW = 0
    private var surfaceH = 0

    private data class Segment(
        val x1: Float, val y1: Float,
        val x2: Float, val y2: Float,
        val widthFactor: Float,
    )

    private val segments = mutableListOf<Segment>()
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
        segments.clear()
        if (surfaceW <= 0) return

        val startX = surfaceW * (0.2f + Random.nextFloat() * 0.6f)
        val endX = startX + (Random.nextFloat() - 0.5f) * surfaceW * 0.3f
        val endY = surfaceH * (0.42f + Random.nextFloat() * 0.18f)
        val mainSegs = 20
        val dy = endY / mainSegs
        val dx = (endX - startX) / mainSegs
        var x = startX
        var y = 0f
        for (i in 1..mainSegs) {
            val nx = x + dx + (Random.nextFloat() - 0.5f) * surfaceW * 0.07f
            val ny = y + dy
            // Main trunk tapers from 1.0 at top → 0.55 at bottom
            val w = 1f - (i.toFloat() / mainSegs) * 0.45f
            segments.add(Segment(x, y, nx, ny, w))
            // Forks more likely in upper middle (30-70% of bolt height)
            val forkChance = if (i in (mainSegs / 4)..(mainSegs * 3 / 4)) 0.55f else 0.25f
            if (Random.nextFloat() < forkChance) {
                generateFork(
                    nx, ny,
                    depth = 1,
                    maxDepth = 2,
                    maxLen = surfaceH * (0.05f + Random.nextFloat() * 0.06f),
                    widthSeed = 0.55f,
                    sideBias = if (Random.nextBoolean()) 1f else -1f,
                )
            }
            x = nx
            y = ny
        }
    }

    private fun generateFork(
        ox: Float, oy: Float,
        depth: Int, maxDepth: Int,
        maxLen: Float,
        widthSeed: Float,
        sideBias: Float,
    ) {
        val forkSegs = 5 + Random.nextInt(4)
        val baseAngle = sideBias * (0.4f + Random.nextFloat() * 0.5f)  // mostly sideways
        val stepLen = maxLen / forkSegs
        var fx = ox
        var fy = oy
        for (j in 1..forkSegs) {
            val t = j.toFloat() / forkSegs
            val jitter = (Random.nextFloat() - 0.5f) * 0.45f
            val angle = baseAngle + jitter
            val nx = fx + sin(angle.toDouble()).toFloat() * stepLen
            val ny = fy + cos(angle.toDouble()).toFloat() * stepLen * 0.7f + stepLen * 0.35f
            // Taper aggressively toward the tip
            val w = (widthSeed * (1f - t * 0.85f)).coerceAtLeast(0.08f)
            segments.add(Segment(fx, fy, nx, ny, w))
            // Recursive sub-fork (only if deeper allowed)
            if (depth < maxDepth && j in 2 until forkSegs - 1 && Random.nextFloat() < 0.30f) {
                generateFork(
                    nx, ny,
                    depth = depth + 1,
                    maxDepth = maxDepth,
                    maxLen = maxLen * 0.5f,
                    widthSeed = widthSeed * 0.55f,
                    sideBias = if (Random.nextBoolean()) 1f else -1f,
                )
            }
            fx = nx
            fy = ny
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
        val outerBase = surfaceW * 0.020f
        val midBase = surfaceW * 0.009f
        val coreBase = surfaceW * 0.0030f

        // Three layered passes for glow effect — each segment scaled by its widthFactor
        // Outer halo (blue, semi-transparent)
        paint.color = Color.argb((alpha * 0.22f).toInt().coerceIn(0, 255), 170, 200, 255)
        for (s in segments) {
            paint.strokeWidth = (outerBase * s.widthFactor).coerceAtLeast(1f)
            canvas.drawLine(s.x1, s.y1, s.x2, s.y2, paint)
        }
        // Mid layer (light blue)
        paint.color = Color.argb((alpha * 0.65f).toInt().coerceIn(0, 255), 215, 230, 255)
        for (s in segments) {
            paint.strokeWidth = (midBase * s.widthFactor).coerceAtLeast(0.8f)
            canvas.drawLine(s.x1, s.y1, s.x2, s.y2, paint)
        }
        // Bright white core
        paint.color = Color.argb(alpha, 255, 255, 255)
        for (s in segments) {
            paint.strokeWidth = (coreBase * s.widthFactor).coerceAtLeast(0.5f)
            canvas.drawLine(s.x1, s.y1, s.x2, s.y2, paint)
        }
    }
}
