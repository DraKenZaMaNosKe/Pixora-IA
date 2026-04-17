package com.orbix.pixora.renderers

import android.content.Context
import android.graphics.*
import kotlin.math.sin
import kotlin.random.Random

/**
 * Renders animated fish sprites over a background image.
 * Fish swim with sinusoidal paths, flip direction when re-entering,
 * and their fin animation plays independently from movement.
 *
 * Usage:
 *   val renderer = AquariumRenderer(context)
 *   renderer.surfaceWidth = w
 *   renderer.surfaceHeight = h
 *   renderer.loadFishSprites("aquarium/betta")  // folder in assets
 *   renderer.addFish(3)  // spawn 3 fish
 *   // In draw loop:
 *   renderer.draw(canvas)
 */
class AquariumRenderer(private val context: Context) {

    var surfaceWidth = 0
    var surfaceHeight = 0

    private val fishes = mutableListOf<Fish>()
    private val spriteCache = mutableMapOf<String, List<Bitmap>>()
    val fishCount get() = fishes.size

    // ── Fish data class ──────────────────────────────────────────
    data class Fish(
        var x: Float,
        var y: Float,
        var speedX: Float,           // pixels per frame (negative = left)
        var amplitudeY: Float,       // vertical wave amplitude
        var phaseY: Float,           // vertical wave phase
        var waveSpeed: Float,        // how fast the wave oscillates
        var frameIndex: Int,         // current animation frame
        var frameTimer: Int,         // counts draw calls for frame advance
        var framesPerTick: Int,      // draw calls between frame advances
        var goingRight: Boolean,     // direction
        var scale: Float,            // size multiplier (variety)
        var spriteFolder: String,    // which sprite set to use
    )

    // ── Load sprites from assets OR filesystem ────────────────────
    // mirrorOnLoad: flip each frame horizontally once at decode time. Use for sprite
    // sets whose source faces right — the renderer assumes left-facing as canonical.
    // Checks filesystem cache first (sprites downloaded from Supabase); falls back to
    // bundled APK assets if the cache dir doesn't exist.
    fun loadFishSprites(assetFolder: String, mirrorOnLoad: Boolean = false) {
        if (spriteCache.containsKey(assetFolder)) return
        try {
            // Check filesystem cache first (downloaded sprites)
            val cacheDir = java.io.File(context.filesDir, "sprites/$assetFolder")
            val fromFiles = cacheDir.isDirectory
            val fileList = if (fromFiles) {
                cacheDir.listFiles()?.filter { it.name.endsWith(".png") }?.sorted()?.map { it.name } ?: emptyList()
            } else {
                context.assets.list(assetFolder)?.filter { it.endsWith(".png") }?.sorted() ?: emptyList()
            }
            if (fileList.isEmpty()) return

            val bitmaps = fileList.mapNotNull { filename ->
                val raw = if (fromFiles) {
                    BitmapFactory.decodeFile("${cacheDir.absolutePath}/$filename")
                } else {
                    context.assets.open("$assetFolder/$filename").use { stream ->
                        BitmapFactory.decodeStream(stream)
                    }
                }
                if (raw == null) return@mapNotNull null
                if (mirrorOnLoad) {
                    val m = Matrix().apply { postScale(-1f, 1f) }
                    val flipped = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, m, true)
                    raw.recycle()
                    flipped
                } else raw
            }
            spriteCache[assetFolder] = bitmaps
            val src = if (fromFiles) "files" else "assets"
            android.util.Log.d("AquariumRenderer", "Loaded ${bitmaps.size} frames from $src:$assetFolder (mirrored=$mirrorOnLoad)")
        } catch (e: Exception) {
            android.util.Log.e("AquariumRenderer", "Failed to load sprites: $e")
        }
    }

    // ── Add fish ─────────────────────────────────────────────────
    fun addFish(
        count: Int,
        spriteFolder: String = "aquarium/betta",
        scaleMin: Float = 0.6f,
        scaleMax: Float = 1.0f,
        speedMin: Float = 1f,
        speedMax: Float = 3f,
    ) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        loadFishSprites(spriteFolder)

        for (i in 0 until count) {
            val goingRight = Random.nextBoolean()
            val speed = Random.nextFloat() * (speedMax - speedMin) + speedMin
            fishes.add(Fish(
                x = Random.nextFloat() * surfaceWidth,
                y = Random.nextFloat() * (surfaceHeight * 0.6f) + surfaceHeight * 0.15f,
                speedX = if (goingRight) speed else -speed,
                amplitudeY = Random.nextFloat() * 30f + 10f,  // 10-40 px wave
                phaseY = Random.nextFloat() * Math.PI.toFloat() * 2f,
                waveSpeed = Random.nextFloat() * 0.03f + 0.01f,  // wave frequency
                frameIndex = Random.nextInt(0, 30),  // start at random frame
                frameTimer = 0,
                framesPerTick = Random.nextInt(2, 4),  // animation speed variety
                goingRight = goingRight,
                scale = Random.nextFloat() * (scaleMax - scaleMin) + scaleMin,
                spriteFolder = spriteFolder,
            ))
        }
    }

    // ── Draw ─────────────────────────────────────────────────────
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        for (fish in fishes) {
            val sprites = spriteCache[fish.spriteFolder] ?: continue
            if (sprites.isEmpty()) continue

            // Advance animation frame
            fish.frameTimer++
            if (fish.frameTimer >= fish.framesPerTick) {
                fish.frameTimer = 0
                fish.frameIndex = (fish.frameIndex + 1) % sprites.size
            }

            // Move horizontally
            fish.x += fish.speedX

            // Vertical wave motion
            fish.phaseY += fish.waveSpeed
            val waveY = sin(fish.phaseY.toDouble()).toFloat() * fish.amplitudeY

            // Wrap around screen
            val sprite = sprites[fish.frameIndex % sprites.size]
            if (sprite.isRecycled) continue
            val scaledW = sprite.width * fish.scale
            if (fish.goingRight && fish.x > surfaceWidth + scaledW) {
                // Exit right → re-enter left, maybe change direction
                fish.x = -scaledW
                fish.y = Random.nextFloat() * (surfaceHeight * 0.6f) + surfaceHeight * 0.15f
                fish.goingRight = Random.nextBoolean()
                fish.speedX = (Random.nextFloat() * 2f + 1f) * if (fish.goingRight) 1f else -1f
            } else if (!fish.goingRight && fish.x < -scaledW) {
                // Exit left → re-enter right, maybe change direction
                fish.x = surfaceWidth + scaledW
                fish.y = Random.nextFloat() * (surfaceHeight * 0.6f) + surfaceHeight * 0.15f
                fish.goingRight = Random.nextBoolean()
                fish.speedX = (Random.nextFloat() * 2f + 1f) * if (fish.goingRight) 1f else -1f
            }

            // Draw the fish
            val drawY = fish.y + waveY
            canvas.save()
            canvas.translate(fish.x, drawY)
            canvas.scale(fish.scale, fish.scale)

            // Flip horizontally if going right (sprites face left by default)
            if (fish.goingRight) {
                canvas.scale(-1f, 1f, sprite.width / 2f, sprite.height / 2f)
            }

            canvas.drawBitmap(sprite, 0f, 0f, paint)
            canvas.restore()
        }
    }

    // ── Position a sprite at a fixed point, fully stationary (for perched owls, etc.) ──
    fun setLastFishPosition(x: Float, y: Float) {
        if (fishes.isNotEmpty()) {
            val f = fishes.last()
            f.x = x
            f.y = y
            f.speedX = 0f
            f.amplitudeY = 0f
            f.waveSpeed = 0f
        }
    }

    // ── Touch interaction: fish flee from tap ────────────────────
    fun onTouch(touchX: Float, touchY: Float) {
        for (fish in fishes) {
            val dx = fish.x - touchX
            val dy = fish.y - touchY
            val dist = Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()
            if (dist < 300f) {
                // Flee: reverse direction and speed up temporarily
                fish.goingRight = touchX > fish.x  // swim away from touch
                fish.speedX = (Random.nextFloat() * 4f + 3f) * if (fish.goingRight) 1f else -1f
                fish.amplitudeY = Random.nextFloat() * 50f + 20f  // more erratic
            }
        }
    }

    // ── Cleanup ──────────────────────────────────────────────────
    fun recycle() {
        for ((_, bitmaps) in spriteCache) {
            bitmaps.forEach { if (!it.isRecycled) it.recycle() }
        }
        spriteCache.clear()
        fishes.clear()
    }
}
