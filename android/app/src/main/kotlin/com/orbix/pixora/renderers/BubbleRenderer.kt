package com.orbix.pixora.renderers

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kotlin.math.sin
import kotlin.random.Random

/**
 * Lightweight bubble effect for the aquarium wallpaper.
 * Bubbles spawn near the bottom, rise with sinusoidal wobble, pop at the top.
 * Pure code — no bitmap assets, ~negligible memory.
 */
class BubbleRenderer {

    var surfaceWidth = 0
    var surfaceHeight = 0

    private data class Bubble(
        var baseX: Float,
        var x: Float,
        var y: Float,
        var radius: Float,
        var speed: Float,
        var wobbleAmp: Float,
        var wobblePhase: Float,
        var wobbleSpeed: Float,
    )

    private val bubbles = mutableListOf<Bubble>()
    private val maxBubbles = 20
    private var spawnCooldown = 0

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(70, 220, 240, 255)
        style = Paint.Style.FILL
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(130, 255, 255, 255)
        style = Paint.Style.STROKE
        strokeWidth = 1.2f
    }
    private val highlightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(200, 255, 255, 255)
        style = Paint.Style.FILL
    }

    fun update() {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        // Spawn rate: on average ~1 bubble per second at 30 FPS
        spawnCooldown--
        if (spawnCooldown <= 0 && bubbles.size < maxBubbles) {
            spawnCooldown = Random.nextInt(15, 50)
            val baseX = Random.nextFloat() * surfaceWidth
            bubbles.add(
                Bubble(
                    baseX = baseX,
                    x = baseX,
                    y = surfaceHeight.toFloat() - Random.nextFloat() * 80f,
                    radius = Random.nextFloat() * 4f + 3f,        // 3-7 px
                    speed = Random.nextFloat() * 2.5f + 1f,       // 1-3.5 px/frame
                    wobbleAmp = Random.nextFloat() * 18f + 6f,    // 6-24 px lateral sway
                    wobblePhase = Random.nextFloat() * (Math.PI.toFloat() * 2f),
                    wobbleSpeed = Random.nextFloat() * 0.08f + 0.03f,
                )
            )
        }

        val iter = bubbles.iterator()
        while (iter.hasNext()) {
            val b = iter.next()
            b.y -= b.speed
            b.wobblePhase += b.wobbleSpeed
            b.x = b.baseX + sin(b.wobblePhase.toDouble()).toFloat() * b.wobbleAmp
            if (b.y + b.radius < 0) iter.remove()
        }
    }

    fun draw(canvas: Canvas) {
        for (b in bubbles) {
            canvas.drawCircle(b.x, b.y, b.radius, fillPaint)
            canvas.drawCircle(b.x, b.y, b.radius, strokePaint)
            // Small highlight in the upper-left for a glassy look
            canvas.drawCircle(
                b.x - b.radius * 0.35f,
                b.y - b.radius * 0.35f,
                b.radius * 0.28f,
                highlightPaint
            )
        }
    }

    fun reset() {
        bubbles.clear()
        spawnCooldown = 0
    }
}
