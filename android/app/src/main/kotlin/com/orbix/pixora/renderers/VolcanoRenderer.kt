package com.orbix.pixora.renderers

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kotlin.math.sin
import kotlin.random.Random

/**
 * Pure-particle renderer for the Pixora Volcano Dragon wallpaper.
 * No sprites required — just rising ember particles over the static
 * background + a subtle summit glow pulse.
 *
 * Usage:
 *   val r = VolcanoRenderer()
 *   r.surfaceWidth = w; r.surfaceHeight = h
 *   r.draw(canvas)  // call from WallpaperService render loop
 */
class VolcanoRenderer {

    var surfaceWidth = 0
    var surfaceHeight = 0

    private val embers = mutableListOf<Ember>()
    private var initialized = false
    private var glowPhase = 0f

    private val emberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private data class Ember(
        var x: Float,
        var y: Float,
        var vx: Float,
        var vy: Float,
        var radius: Float,
        var life: Float,         // 0..1 fades out near 0
        var maxLife: Float,
        val color: Int,
    )

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        if (!initialized) {
            spawn(36)
            initialized = true
        }

        // Volcano summit position — roughly center, 55% from top in the
        // source image. Embers spawn from around this area.
        val summitX = surfaceWidth * 0.5f
        val summitY = surfaceHeight * 0.55f

        // Summit glow pulse (eruption breathing effect)
        glowPhase += 0.03f
        val glowAlpha = (110 + 60 * sin(glowPhase.toDouble())).toInt().coerceIn(0, 255)
        glowPaint.color = Color.argb(glowAlpha, 255, 140, 40)
        canvas.drawCircle(summitX, summitY - surfaceHeight * 0.04f,
            surfaceWidth * 0.12f, glowPaint)
        glowPaint.color = Color.argb((glowAlpha * 0.5).toInt(), 255, 200, 120)
        canvas.drawCircle(summitX, summitY - surfaceHeight * 0.04f,
            surfaceWidth * 0.07f, glowPaint)

        // Update + draw embers
        val iter = embers.iterator()
        while (iter.hasNext()) {
            val e = iter.next()
            e.x += e.vx
            e.y += e.vy
            e.vy *= 0.994f // slight deceleration as they rise
            e.life -= 0.012f
            if (e.life <= 0f || e.y < -20f) {
                iter.remove()
                continue
            }
            val alpha = ((e.life / e.maxLife) * 255).toInt().coerceIn(0, 255)
            emberPaint.color = Color.argb(
                alpha,
                Color.red(e.color),
                Color.green(e.color),
                Color.blue(e.color)
            )
            canvas.drawCircle(e.x, e.y, e.radius, emberPaint)
        }

        // Maintain ember count — respawn as they die
        while (embers.size < 36) {
            spawn(1)
        }
    }

    private fun spawn(n: Int) {
        val summitX = surfaceWidth * 0.5f
        val summitY = surfaceHeight * 0.55f
        val colors = intArrayOf(
            0xFFFFB040.toInt(), 0xFFFF8820.toInt(),
            0xFFFFCC60.toInt(), 0xFFFF6A10.toInt(),
        )
        repeat(n) {
            val angle = Random.nextFloat() * 0.8f - 0.4f // ±23° from vertical
            val speed = Random.nextFloat() * 1.3f + 0.7f
            val life = Random.nextFloat() * 0.7f + 0.6f
            embers.add(
                Ember(
                    x = summitX + (Random.nextFloat() - 0.5f) * surfaceWidth * 0.12f,
                    y = summitY + (Random.nextFloat() - 0.5f) * 40f,
                    vx = sin(angle.toDouble()).toFloat() * speed * 0.3f,
                    vy = -speed * 1.4f,
                    radius = Random.nextFloat() * 2.2f + 1.4f,
                    life = life,
                    maxLife = life,
                    color = colors[Random.nextInt(colors.size)],
                )
            )
        }
    }

    fun reset() {
        embers.clear()
        initialized = false
        glowPhase = 0f
    }
}
