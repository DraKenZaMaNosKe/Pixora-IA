package com.orbix.pixora.renderers

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import kotlin.math.sin
import kotlin.random.Random

/**
 * Code-driven firefly overlay for enchanted forest wallpapers.
 * Each firefly is a warm glowing dot that drifts slowly with Brownian motion
 * and pulses in/out (alpha cycle). Pure code — zero bitmap assets.
 */
class FireflyRenderer {

    var surfaceWidth = 0
    var surfaceHeight = 0

    private data class Firefly(
        var x: Float,
        var y: Float,
        var driftX: Float,
        var driftY: Float,
        var radius: Float,
        var glowRadius: Float,
        var pulsePhase: Float,
        var pulseSpeed: Float,
        var life: Float,
        var maxLife: Float,
    )

    private val fireflies = mutableListOf<Firefly>()
    private val maxFireflies = 35
    private var frame = 0
    private var spawnCooldown = 0

    private val corePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    fun update() {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        frame++

        // Spawn
        spawnCooldown--
        if (spawnCooldown <= 0 && fireflies.size < maxFireflies) {
            spawnCooldown = Random.nextInt(3, 12)
            fireflies.add(Firefly(
                x = Random.nextFloat() * surfaceWidth,
                y = Random.nextFloat() * surfaceHeight * 0.75f + surfaceHeight * 0.05f,
                driftX = (Random.nextFloat() - 0.5f) * 1.2f,
                driftY = (Random.nextFloat() - 0.5f) * 0.8f,
                radius = Random.nextFloat() * 2.5f + 2f,
                glowRadius = Random.nextFloat() * 12f + 10f,
                pulsePhase = Random.nextFloat() * (Math.PI.toFloat() * 2f),
                pulseSpeed = Random.nextFloat() * 0.06f + 0.02f,
                life = 0f,
                maxLife = Random.nextFloat() * 400f + 200f,
            ))
        }

        // Update each firefly
        val iter = fireflies.iterator()
        while (iter.hasNext()) {
            val f = iter.next()
            f.life++

            // Slow Brownian drift (change direction occasionally)
            if (Random.nextFloat() < 0.02f) {
                f.driftX = (Random.nextFloat() - 0.5f) * 1.2f
                f.driftY = (Random.nextFloat() - 0.5f) * 0.8f
            }
            f.x += f.driftX
            f.y += f.driftY

            // Wrap around screen edges softly
            if (f.x < -20f) f.x = surfaceWidth + 20f
            if (f.x > surfaceWidth + 20f) f.x = -20f
            if (f.y < -20f) f.y = surfaceHeight * 0.8f
            if (f.y > surfaceHeight * 0.85f) f.y = surfaceHeight * 0.05f

            // Remove when life expires
            if (f.life > f.maxLife) iter.remove()
        }
    }

    fun draw(canvas: Canvas) {
        for (f in fireflies) {
            // Pulse: main oscillation
            val pulse = 0.5f + 0.5f * sin((f.life * f.pulseSpeed + f.pulsePhase).toDouble()).toFloat()

            // Fade in during first 30 frames, fade out during last 30
            val fadeIn = (f.life / 30f).coerceAtMost(1f)
            val fadeOut = ((f.maxLife - f.life) / 30f).coerceAtMost(1f)
            val alpha = pulse * fadeIn * fadeOut

            if (alpha < 0.02f) continue

            // Warm yellow-green glow (outer)
            val glowAlpha = (alpha * 100f).toInt().coerceIn(0, 180)
            glowPaint.shader = RadialGradient(
                f.x, f.y, f.glowRadius * (0.8f + alpha * 0.4f),
                Color.argb(glowAlpha, 200, 220, 80),
                Color.argb(0, 180, 200, 60),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(f.x, f.y, f.glowRadius * (0.8f + alpha * 0.4f), glowPaint)

            // Bright core (inner)
            val coreAlpha = (alpha * 255f).toInt().coerceIn(0, 255)
            corePaint.color = Color.argb(coreAlpha, 255, 255, 200)
            canvas.drawCircle(f.x, f.y, f.radius * (0.6f + alpha * 0.4f), corePaint)
        }
    }

    fun reset() {
        fireflies.clear()
        spawnCooldown = 0
        frame = 0
    }
}
