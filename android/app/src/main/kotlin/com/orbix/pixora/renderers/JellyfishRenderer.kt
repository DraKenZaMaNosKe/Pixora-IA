package com.orbix.pixora.renderers

import android.content.Context
import android.graphics.*
import kotlin.math.sin
import kotlin.random.Random

/**
 * Renders animated jellyfish sprites over a deep-ocean background.
 * Unlike AquariumRenderer (horizontal swimmers), jellies drift upward
 * through the water column with gentle sinusoidal horizontal sway.
 * When they exit the top they respawn at the bottom at a new x position.
 *
 * Each jelly has its own sprite folder (PNG sequence) and cycles through
 * the frames to play the bell-pulse animation baked into the sprites.
 */
class JellyfishRenderer(private val context: Context) {

    var surfaceWidth = 0
    var surfaceHeight = 0

    private val jellies = mutableListOf<Jelly>()
    private val spriteCache = mutableMapOf<String, List<Bitmap>>()
    val jellyCount get() = jellies.size

    data class Jelly(
        var x: Float,
        var y: Float,
        var speedY: Float,         // pixels per frame upward (negative = rising)
        var swayAmplitude: Float,  // horizontal sine amplitude in px
        var swayPhase: Float,      // current sway phase
        var swaySpeed: Float,      // sway angular velocity
        var baseX: Float,          // center of sway oscillation
        var frameIndex: Int,
        var frameTimer: Int,
        var framesPerTick: Int,
        var scale: Float,
        var alpha: Float,          // 0..1 — depth atmospheric attenuation
        var spriteFolder: String,
    )

    fun hasSprites(assetFolder: String): Boolean =
        spriteCache[assetFolder]?.isNotEmpty() == true

    fun loadSprites(assetFolder: String) {
        if (spriteCache.containsKey(assetFolder)) return
        try {
            val cacheDir = java.io.File(context.filesDir, "sprites/$assetFolder")
            val fromFiles = cacheDir.isDirectory
            val fileList = if (fromFiles) {
                cacheDir.listFiles()?.filter { it.name.endsWith(".png") }
                    ?.sorted()?.map { it.name } ?: emptyList()
            } else {
                context.assets.list(assetFolder)
                    ?.filter { it.endsWith(".png") }?.sorted() ?: emptyList()
            }
            if (fileList.isEmpty()) {
                android.util.Log.w("JellyfishRenderer", "No frames found for $assetFolder")
                return
            }

            val opts = BitmapFactory.Options().apply {
                inSampleSize = 2
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            val bitmaps = fileList.mapNotNull { filename ->
                if (fromFiles) {
                    BitmapFactory.decodeFile("${cacheDir.absolutePath}/$filename", opts)
                } else {
                    context.assets.open("$assetFolder/$filename").use { stream ->
                        BitmapFactory.decodeStream(stream, null, opts)
                    }
                }
            }
            spriteCache[assetFolder] = bitmaps
            val src = if (fromFiles) "files" else "assets"
            android.util.Log.d(
                "JellyfishRenderer",
                "Loaded ${bitmaps.size} frames from $src:$assetFolder"
            )
            System.gc()
        } catch (e: Exception) {
            android.util.Log.e("JellyfishRenderer", "Failed to load $assetFolder: $e")
        }
    }

    /**
     * Spawn [count] jellies of the given sprite set at random positions.
     * Each jelly gets its own scale (depth), speed and sway params.
     */
    fun addJellies(
        count: Int,
        spriteFolder: String,
        scaleMin: Float = 0.5f,
        scaleMax: Float = 1.0f,
        speedMin: Float = 0.3f,
        speedMax: Float = 0.9f,
        swayAmpMin: Float = 15f,
        swayAmpMax: Float = 40f,
    ) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        loadSprites(spriteFolder)

        for (i in 0 until count) {
            val scale = Random.nextFloat() * (scaleMax - scaleMin) + scaleMin
            val baseX = Random.nextFloat() * surfaceWidth
            val speed = Random.nextFloat() * (speedMax - speedMin) + speedMin
            // Smaller (distant) jellies move slower and fade more
            val depthFactor = (scale - scaleMin) / (scaleMax - scaleMin + 0.001f)
            val alpha = 0.45f + depthFactor * 0.55f
            jellies.add(
                Jelly(
                    x = baseX,
                    y = Random.nextFloat() * surfaceHeight * 1.2f, // staggered vertically
                    speedY = -speed * (0.6f + depthFactor * 0.8f),
                    swayAmplitude = Random.nextFloat() * (swayAmpMax - swayAmpMin) + swayAmpMin,
                    swayPhase = Random.nextFloat() * Math.PI.toFloat() * 2f,
                    swaySpeed = Random.nextFloat() * 0.015f + 0.005f,
                    baseX = baseX,
                    frameIndex = Random.nextInt(0, 20),
                    frameTimer = 0,
                    framesPerTick = Random.nextInt(2, 4),
                    scale = scale,
                    alpha = alpha,
                    spriteFolder = spriteFolder,
                )
            )
        }
    }

    private val paint = Paint(Paint.FILTER_BITMAP_FLAG).apply {
        isAntiAlias = true
    }

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        // Sort by scale so smaller (distant) jellies draw first — correct depth order.
        val sorted = jellies.sortedBy { it.scale }

        for (jelly in sorted) {
            val sprites = spriteCache[jelly.spriteFolder] ?: continue
            if (sprites.isEmpty()) continue

            // Advance animation frame
            jelly.frameTimer++
            if (jelly.frameTimer >= jelly.framesPerTick) {
                jelly.frameTimer = 0
                jelly.frameIndex = (jelly.frameIndex + 1) % sprites.size
            }

            // Rise upward
            jelly.y += jelly.speedY

            // Sinusoidal horizontal sway
            jelly.swayPhase += jelly.swaySpeed
            jelly.x = jelly.baseX + sin(jelly.swayPhase.toDouble()).toFloat() * jelly.swayAmplitude

            val sprite = sprites[jelly.frameIndex % sprites.size]
            if (sprite.isRecycled) continue

            val scaledW = sprite.width * jelly.scale
            val scaledH = sprite.height * jelly.scale

            // Respawn at bottom when fully exited top
            if (jelly.y + scaledH < 0f) {
                jelly.y = surfaceHeight + scaledH * 0.1f
                jelly.baseX = Random.nextFloat() * surfaceWidth
                jelly.swayPhase = Random.nextFloat() * Math.PI.toFloat() * 2f
            }

            // Skip if way off-screen horizontally (shouldn't happen with sway)
            if (jelly.x + scaledW / 2 < -50f || jelly.x - scaledW / 2 > surfaceWidth + 50f) continue

            // Apply depth alpha
            paint.alpha = (jelly.alpha * 255f).toInt().coerceIn(0, 255)

            canvas.save()
            canvas.translate(jelly.x - scaledW / 2, jelly.y)
            canvas.scale(jelly.scale, jelly.scale)
            canvas.drawBitmap(sprite, 0f, 0f, paint)
            canvas.restore()
        }
        paint.alpha = 255
    }

    fun recycle() {
        for ((_, bitmaps) in spriteCache) {
            bitmaps.forEach { if (!it.isRecycled) it.recycle() }
        }
        spriteCache.clear()
        jellies.clear()
    }

    fun reset() {
        jellies.clear()
    }
}
