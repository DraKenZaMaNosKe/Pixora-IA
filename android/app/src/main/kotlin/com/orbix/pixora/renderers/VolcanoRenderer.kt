package com.orbix.pixora.renderers

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * Pixora Volcano Dragon live wallpaper renderer (Canvas-based).
 *
 * Layers:
 *   - Background image (drawn by PixoraWallpaperService before this renderer)
 *   - Particle FX (embers rising + summit glow pulse)
 *   - Sprite layer (2 dragons orbiting + 3 bats + cinematic phoenix + lightning)
 *
 * Cinematic events:
 *   - Lightning every ~10s (2s flash on screen)
 *   - Phoenix every ~25s (5s rise from bottom)
 */
class VolcanoRenderer(private val context: Context) {

    var surfaceWidth = 0
    var surfaceHeight = 0

    // ── Particle state ─────────────────────────────────
    private val embers = mutableListOf<Ember>()
    private var initialized = false
    private var glowPhase = 0f

    private val emberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    private data class Ember(
        var x: Float, var y: Float,
        var vx: Float, var vy: Float,
        var radius: Float,
        var life: Float, var maxLife: Float,
        val color: Int,
    )

    // ── Sprite system ──────────────────────────────────
    private val dragonMain = SpriteSheet(context, "v160_sprites/dragon_main")
    private val dragonSecondary = SpriteSheet(context, "v160_sprites/dragon_secondary")
    private val bat = SpriteSheet(context, "v160_sprites/bat")
    private val phoenix = SpriteSheet(context, "v160_sprites/phoenix")
    private val lightning = SpriteSheet(context, "v160_sprites/lightning")

    // Frame counter (60fps assumed) — drives cinematic event timers
    private var tick = 0L

    // Phoenix one-shot state
    private var phoenixActive = false
    private var phoenixStartTick = 0L
    private val phoenixIntervalTicks = 25 * 60L   // every 25s
    private val phoenixDurationTicks = 5 * 60L    // 5s sequence

    // Lightning one-shot state
    private var lightningActive = false
    private var lightningStartTick = 0L
    private val lightningIntervalTicks = 10 * 60L // every 10s
    private val lightningDurationTicks = 2 * 60L  // 2s

    // Bat positions (3 fixed wandering points)
    private val batCenters = arrayOf(
        floatArrayOf(0.20f, 0.18f),
        floatArrayOf(0.82f, 0.22f),
        floatArrayOf(0.50f, 0.12f),
    )

    // Dragon orbits — angle starts at random offsets so they're not synced
    private var dragonMainAngle = 0f
    private var dragonSecAngle = Math.PI.toFloat()

    // ── Public API ─────────────────────────────────────

    fun ensureLoaded() {
        if (!dragonMain.loaded) dragonMain.load(framesPerTick = 2)
        if (!dragonSecondary.loaded) dragonSecondary.load(framesPerTick = 2)
        if (!bat.loaded) bat.load(framesPerTick = 2)
        if (!phoenix.loaded) phoenix.load(framesPerTick = 2)
        if (!lightning.loaded) lightning.load(framesPerTick = 1)
    }

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        ensureLoaded()
        if (!initialized) {
            spawnEmber(36)
            initialized = true
        }
        tick++

        // Particle layer
        drawSummitGlow(canvas)
        drawEmbers(canvas)

        // Cinematic events (drawn BEFORE sprites so dragons are on top of lightning)
        drawLightning(canvas)

        // Sprite layer — orbiting dragons + bats
        drawDragons(canvas)
        drawBats(canvas)

        // Phoenix on top of everything (HERO event)
        drawPhoenix(canvas)
    }

    // ── Particle FX ────────────────────────────────────

    private fun drawSummitGlow(canvas: Canvas) {
        val summitX = surfaceWidth * 0.5f
        val summitY = surfaceHeight * 0.55f
        glowPhase += 0.03f
        val glowAlpha = (110 + 60 * sin(glowPhase.toDouble())).toInt().coerceIn(0, 255)
        glowPaint.color = Color.argb(glowAlpha, 255, 140, 40)
        canvas.drawCircle(summitX, summitY - surfaceHeight * 0.04f,
            surfaceWidth * 0.12f, glowPaint)
        glowPaint.color = Color.argb((glowAlpha * 0.5).toInt(), 255, 200, 120)
        canvas.drawCircle(summitX, summitY - surfaceHeight * 0.04f,
            surfaceWidth * 0.07f, glowPaint)
    }

    private fun drawEmbers(canvas: Canvas) {
        val it = embers.iterator()
        while (it.hasNext()) {
            val e = it.next()
            e.x += e.vx
            e.y += e.vy
            e.vy *= 0.994f
            e.life -= 0.012f
            if (e.life <= 0f || e.y < -20f) {
                it.remove()
                continue
            }
            val a = ((e.life / e.maxLife) * 255).toInt().coerceIn(0, 255)
            emberPaint.color = Color.argb(a, Color.red(e.color), Color.green(e.color), Color.blue(e.color))
            canvas.drawCircle(e.x, e.y, e.radius, emberPaint)
        }
        while (embers.size < 36) spawnEmber(1)
    }

    private fun spawnEmber(n: Int) {
        val summitX = surfaceWidth * 0.5f
        val summitY = surfaceHeight * 0.55f
        val colors = intArrayOf(0xFFFFB040.toInt(), 0xFFFF8820.toInt(),
            0xFFFFCC60.toInt(), 0xFFFF6A10.toInt())
        repeat(n) {
            val angle = Random.nextFloat() * 0.8f - 0.4f
            val speed = Random.nextFloat() * 1.3f + 0.7f
            val life = Random.nextFloat() * 0.7f + 0.6f
            embers.add(Ember(
                x = summitX + (Random.nextFloat() - 0.5f) * surfaceWidth * 0.12f,
                y = summitY + (Random.nextFloat() - 0.5f) * 40f,
                vx = sin(angle.toDouble()).toFloat() * speed * 0.3f,
                vy = -speed * 1.4f,
                radius = Random.nextFloat() * 2.2f + 1.4f,
                life = life, maxLife = life,
                color = colors[Random.nextInt(colors.size)],
            ))
        }
    }

    // ── Sprite drawing ─────────────────────────────────

    private fun drawDragons(canvas: Canvas) {
        // Main dragon — orbits summit at radius ~30% of screen width
        val cx = surfaceWidth * 0.5f
        val cy = surfaceHeight * 0.45f
        val rMain = surfaceWidth * 0.32f
        dragonMainAngle += 0.012f
        val dx = cx + cos(dragonMainAngle.toDouble()).toFloat() * rMain
        val dy = cy + sin(dragonMainAngle.toDouble()).toFloat() * rMain * 0.6f
        // Flip when going right-to-left for correct facing
        val flipMain = sin(dragonMainAngle.toDouble()) < 0
        dragonMain.advance()
        dragonMain.drawAt(canvas, dx, dy,
            scale = surfaceWidth * 0.0014f,
            flipX = flipMain)

        // Secondary dragon — wider radius, opposite direction
        val rSec = surfaceWidth * 0.42f
        dragonSecAngle -= 0.008f
        val sx = cx + cos(dragonSecAngle.toDouble()).toFloat() * rSec
        val sy = cy + sin(dragonSecAngle.toDouble()).toFloat() * rSec * 0.55f
        val flipSec = sin(dragonSecAngle.toDouble()) > 0
        dragonSecondary.advance()
        dragonSecondary.drawAt(canvas, sx, sy,
            scale = surfaceWidth * 0.0009f,
            flipX = flipSec, alpha = 200)
    }

    private fun drawBats(canvas: Canvas) {
        bat.advance()
        for ((i, p) in batCenters.withIndex()) {
            // Subtle wandering using sin of independent phases
            val phase = tick * 0.02f + i * 1.3f
            val ox = sin(phase.toDouble()).toFloat() * surfaceWidth * 0.04f
            val oy = cos((phase * 1.4).toDouble()).toFloat() * surfaceHeight * 0.02f
            val bx = surfaceWidth * p[0] + ox
            val by = surfaceHeight * p[1] + oy
            bat.drawAt(canvas, bx, by, scale = surfaceWidth * 0.0010f, flipX = i % 2 == 0)
        }
    }

    // ── Cinematic events ───────────────────────────────

    private fun drawLightning(canvas: Canvas) {
        if (!lightningActive && tick > 0 && tick % lightningIntervalTicks == 0L) {
            lightningActive = true
            lightningStartTick = tick
            lightning.reset()
        }
        if (lightningActive) {
            lightning.advance()
            val elapsed = tick - lightningStartTick
            // Fade in/out across 2s
            val t = elapsed.toFloat() / lightningDurationTicks
            val alpha = (255 * if (t < 0.1f) t / 0.1f
                              else if (t > 0.7f) (1 - (t - 0.7f) / 0.3f).coerceAtLeast(0f)
                              else 1f).toInt().coerceIn(0, 255)
            lightning.drawAt(canvas,
                surfaceWidth * 0.55f, surfaceHeight * 0.18f,
                scale = surfaceWidth * 0.0024f, alpha = alpha)
            if (elapsed >= lightningDurationTicks) lightningActive = false
        }
    }

    private fun drawPhoenix(canvas: Canvas) {
        if (!phoenixActive && tick > 0 && tick % phoenixIntervalTicks == 0L) {
            phoenixActive = true
            phoenixStartTick = tick
            phoenix.reset()
        }
        if (phoenixActive) {
            phoenix.advance()
            val elapsed = tick - phoenixStartTick
            val t = (elapsed.toFloat() / phoenixDurationTicks).coerceIn(0f, 1f)
            // Rise from y=95% to y=20% over the 5s
            val y = surfaceHeight * (0.95f - 0.75f * t)
            val x = surfaceWidth * 0.5f
            // Scale grows then shrinks, alpha fades in then out
            val scaleProgress = if (t < 0.5f) t * 2f else 1f - (t - 0.5f) * 0.6f
            val scale = surfaceWidth * 0.0028f * scaleProgress
            val alpha = (255 * if (t < 0.1f) t / 0.1f
                              else if (t > 0.85f) (1 - (t - 0.85f) / 0.15f).coerceAtLeast(0f)
                              else 1f).toInt().coerceIn(0, 255)
            phoenix.drawAt(canvas, x, y, scale = scale, alpha = alpha)
            if (elapsed >= phoenixDurationTicks) phoenixActive = false
        }
    }

    // ── Lifecycle ──────────────────────────────────────

    fun reset() {
        embers.clear()
        initialized = false
        glowPhase = 0f
        phoenixActive = false
        lightningActive = false
        tick = 0
    }

    fun release() {
        embers.clear()
        dragonMain.release()
        dragonSecondary.release()
        bat.release()
        phoenix.release()
        lightning.release()
        initialized = false
    }
}
