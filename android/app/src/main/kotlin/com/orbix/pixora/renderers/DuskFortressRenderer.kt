package com.orbix.pixora.renderers

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * Pixora Dusk Fortress live wallpaper renderer (Canvas-based).
 *
 * Layers:
 *   - Background image (drawn by PixoraWallpaperService before this)
 *   - Particle FX (torch flicker + ash motes drifting + valley wisps)
 *   - Sprite layer (owl crossing top, 3 crows, 5 bats from tower, dragon orbiting tower)
 *   - Cinematic lightning every ~14s
 */
class DuskFortressRenderer(private val context: Context) {

    var surfaceWidth = 0
    var surfaceHeight = 0

    // ── Particle state ─────────────────────────────────
    private val motes = mutableListOf<Mote>()
    private var initialized = false
    private var flickerPhase = 0f
    private val torchSpots = arrayOf(
        floatArrayOf(0.50f, 0.44f), floatArrayOf(0.54f, 0.38f),
        floatArrayOf(0.47f, 0.41f), floatArrayOf(0.58f, 0.48f),
        floatArrayOf(0.52f, 0.33f),
    )
    // Wisp positions in the valley fog (lower portion of screen)
    private val wispSpots = arrayOf(
        floatArrayOf(0.18f, 0.86f), floatArrayOf(0.36f, 0.92f),
        floatArrayOf(0.55f, 0.88f), floatArrayOf(0.72f, 0.94f),
        floatArrayOf(0.86f, 0.90f),
    )

    private val motePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val torchPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val wispPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    private data class Mote(
        var x: Float, var y: Float,
        var vy: Float, var drift: Float,
        var phase: Float, var radius: Float,
        var life: Float, var maxLife: Float,
    )

    // ── Sprite system ──────────────────────────────────
    private val owl = SpriteSheet(context, "v160_sprites/owl")
    private val crow = SpriteSheet(context, "v160_sprites/crow")
    private val bat = SpriteSheet(context, "v160_sprites/bat")
    private val dragon = SpriteSheet(context, "v160_sprites/dragon_main")
    private val lightning = SpriteSheet(context, "v160_sprites/lightning")

    private var tick = 0L

    // Owl horizontal position (slow translate L→R, looping)
    private var owlPhase = 0f

    // Crow positions (3, different y + speeds)
    private val crowPhases = floatArrayOf(0f, 1.4f, 2.7f)

    // Bat swarm — emerges from tower top every ~12s, 5 bats fan out
    private var batSwarmActive = false
    private var batSwarmStartTick = 0L
    private val batSwarmInterval = 12 * 60L
    private val batSwarmDuration = 5 * 60L
    private val batVelocities = arrayOf(
        floatArrayOf(-1.2f, -0.8f),
        floatArrayOf(1.0f, -0.9f),
        floatArrayOf(-0.4f, -1.1f),
        floatArrayOf(0.5f, -1.0f),
        floatArrayOf(0.0f, -1.3f),
    )

    // Dragon orbits the tallest tower
    private var dragonAngle = 0f

    // Lightning cinematic
    private var lightningActive = false
    private var lightningStartTick = 0L
    private val lightningInterval = 14 * 60L
    private val lightningDuration = 2 * 60L

    // ── Public API ─────────────────────────────────────

    fun ensureLoaded() {
        if (!owl.loaded) owl.load(framesPerTick = 3)
        if (!crow.loaded) crow.load(framesPerTick = 2)
        if (!bat.loaded) bat.load(framesPerTick = 2)
        if (!dragon.loaded) dragon.load(framesPerTick = 2)
        if (!lightning.loaded) lightning.load(framesPerTick = 1)
    }

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        ensureLoaded()
        if (!initialized) {
            spawnMote(28)
            initialized = true
        }
        tick++

        // Particle layer
        drawTorches(canvas)
        drawMotes(canvas)
        drawWisps(canvas)

        // Cinematic lightning
        drawLightning(canvas)

        // Sprite layer
        drawOwl(canvas)
        drawCrows(canvas)
        drawBatSwarm(canvas)
        drawDragon(canvas)
    }

    // ── Particle FX ────────────────────────────────────

    private fun drawTorches(canvas: Canvas) {
        flickerPhase += 0.18f
        for ((i, t) in torchSpots.withIndex()) {
            val phase = flickerPhase + i * 1.17f
            val intensity = 0.65f + 0.35f * sin(phase.toDouble()).toFloat()
            val alpha = (intensity * 200).toInt().coerceIn(0, 220)
            val cx = surfaceWidth * t[0]
            val cy = surfaceHeight * t[1]
            torchPaint.color = Color.argb((alpha * 0.35).toInt(), 255, 150, 60)
            canvas.drawCircle(cx, cy, surfaceWidth * 0.018f, torchPaint)
            torchPaint.color = Color.argb((alpha * 0.6).toInt(), 255, 180, 90)
            canvas.drawCircle(cx, cy, surfaceWidth * 0.010f, torchPaint)
            torchPaint.color = Color.argb(alpha, 255, 220, 140)
            canvas.drawCircle(cx, cy, surfaceWidth * 0.005f, torchPaint)
        }
    }

    private fun drawMotes(canvas: Canvas) {
        val it = motes.iterator()
        while (it.hasNext()) {
            val m = it.next()
            m.phase += 0.04f
            m.x += sin(m.phase.toDouble()).toFloat() * m.drift
            m.y += m.vy
            m.life -= 0.006f
            if (m.life <= 0f || m.y < -10f) {
                it.remove()
                continue
            }
            val alpha = ((m.life / m.maxLife) * 180).toInt().coerceIn(0, 200)
            motePaint.color = Color.argb(alpha, 220, 180, 120)
            canvas.drawCircle(m.x, m.y, m.radius, motePaint)
        }
        while (motes.size < 28) spawnMote(1)
    }

    private fun spawnMote(n: Int) {
        repeat(n) {
            val life = Random.nextFloat() * 0.5f + 0.7f
            motes.add(Mote(
                x = Random.nextFloat() * surfaceWidth,
                y = surfaceHeight * (0.82f + Random.nextFloat() * 0.18f),
                vy = -(Random.nextFloat() * 0.5f + 0.25f),
                drift = Random.nextFloat() * 0.4f + 0.15f,
                phase = Random.nextFloat() * 6.28f,
                radius = Random.nextFloat() * 1.6f + 0.8f,
                life = life, maxLife = life,
            ))
        }
    }

    private fun drawWisps(canvas: Canvas) {
        for ((i, w) in wispSpots.withIndex()) {
            val phase = tick * 0.04f + i * 1.3f
            val intensity = 0.6f + 0.4f * sin(phase.toDouble()).toFloat()
            val cx = surfaceWidth * w[0] + sin((phase * 0.7).toDouble()).toFloat() * 8f
            val cy = surfaceHeight * w[1] + cos((phase * 0.5).toDouble()).toFloat() * 6f
            val rOuter = surfaceWidth * 0.018f
            // Radial gradient for soft halo
            val shader = RadialGradient(
                cx, cy, rOuter,
                Color.argb((220 * intensity).toInt().coerceIn(0, 255), 200, 230, 255),
                Color.argb(0, 200, 230, 255),
                Shader.TileMode.CLAMP
            )
            wispPaint.shader = shader
            canvas.drawCircle(cx, cy, rOuter, wispPaint)
            wispPaint.shader = null
            // Bright core
            wispPaint.color = Color.argb((255 * intensity).toInt().coerceIn(0, 255), 240, 250, 255)
            canvas.drawCircle(cx, cy, surfaceWidth * 0.005f, wispPaint)
        }
    }

    // ── Sprite drawing ─────────────────────────────────

    private fun drawOwl(canvas: Canvas) {
        owl.advance()
        // Owl translates from left-edge (-10%) to right-edge (110%) over ~22s
        owlPhase += 0.0008f
        if (owlPhase > 1f) owlPhase = 0f
        val x = surfaceWidth * (-0.10f + 1.20f * owlPhase)
        val y = surfaceHeight * 0.12f
        owl.drawAt(canvas, x, y, scale = surfaceWidth * 0.0009f)
    }

    private fun drawCrows(canvas: Canvas) {
        crow.advance()
        // 3 crows at different heights, different speeds, different starting offsets
        val speeds = floatArrayOf(0.0014f, 0.0011f, 0.0017f)
        val ys = floatArrayOf(0.22f, 0.28f, 0.18f)
        val flips = booleanArrayOf(false, true, false)
        for (i in 0..2) {
            crowPhases[i] += speeds[i]
            if (crowPhases[i] > 1f) crowPhases[i] = 0f
            val xRange = if (flips[i]) (1.10f - 1.20f * crowPhases[i]) else (-0.10f + 1.20f * crowPhases[i])
            val x = surfaceWidth * xRange
            val y = surfaceHeight * (ys[i] + sin(crowPhases[i] * 6f) * 0.01f)
            crow.drawAt(canvas, x, y, scale = surfaceWidth * 0.00065f, flipX = flips[i])
        }
    }

    private fun drawBatSwarm(canvas: Canvas) {
        if (!batSwarmActive && tick > 0 && tick % batSwarmInterval == 0L) {
            batSwarmActive = true
            batSwarmStartTick = tick
        }
        if (batSwarmActive) {
            bat.advance()
            val elapsed = (tick - batSwarmStartTick).toFloat()
            val t = elapsed / batSwarmDuration
            val originX = surfaceWidth * 0.52f
            val originY = surfaceHeight * 0.32f
            for ((i, v) in batVelocities.withIndex()) {
                val baseTick = elapsed - i * 12 // stagger emergence
                if (baseTick < 0) continue
                val px = originX + v[0] * baseTick * 1.4f
                val py = originY + v[1] * baseTick * 1.4f
                val alpha = (255 * (1f - t).coerceIn(0f, 1f)).toInt()
                bat.drawAt(canvas, px, py, scale = surfaceWidth * 0.0008f,
                    flipX = v[0] > 0, alpha = alpha)
            }
            if (elapsed >= batSwarmDuration) batSwarmActive = false
        }
    }

    private fun drawDragon(canvas: Canvas) {
        dragon.advance()
        // Orbits the tallest tower (around 0.55, 0.36)
        val cx = surfaceWidth * 0.55f
        val cy = surfaceHeight * 0.36f
        val r = surfaceWidth * 0.18f
        dragonAngle += 0.014f
        val dx = cx + cos(dragonAngle.toDouble()).toFloat() * r
        val dy = cy + sin(dragonAngle.toDouble()).toFloat() * r * 0.5f
        val flip = sin(dragonAngle.toDouble()) < 0
        dragon.drawAt(canvas, dx, dy, scale = surfaceWidth * 0.0010f, flipX = flip)
    }

    // ── Cinematic lightning ────────────────────────────

    private fun drawLightning(canvas: Canvas) {
        if (!lightningActive && tick > 0 && tick % lightningInterval == 0L) {
            lightningActive = true
            lightningStartTick = tick
            lightning.reset()
        }
        if (lightningActive) {
            lightning.advance()
            val elapsed = tick - lightningStartTick
            val t = elapsed.toFloat() / lightningDuration
            val alpha = (255 * if (t < 0.1f) t / 0.1f
                              else if (t > 0.7f) (1 - (t - 0.7f) / 0.3f).coerceAtLeast(0f)
                              else 1f).toInt().coerceIn(0, 255)
            lightning.drawAt(canvas,
                surfaceWidth * 0.30f, surfaceHeight * 0.18f,
                scale = surfaceWidth * 0.0024f, alpha = alpha)
            if (elapsed >= lightningDuration) lightningActive = false
        }
    }

    // ── Lifecycle ──────────────────────────────────────

    fun reset() {
        motes.clear()
        initialized = false
        flickerPhase = 0f
        owlPhase = 0f
        for (i in crowPhases.indices) crowPhases[i] = i * 0.4f
        dragonAngle = 0f
        batSwarmActive = false
        lightningActive = false
        tick = 0
    }

    fun release() {
        motes.clear()
        owl.release()
        crow.release()
        bat.release()
        dragon.release()
        lightning.release()
        initialized = false
    }
}
