package com.orbix.pixora.renderers

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.util.Log

/**
 * Generic PNG-frame sprite animation. Reads frame_001.png..frame_NNN.png from
 * a folder under filesDir/sprites/<folder>/ (downloaded) OR APK assets/<folder>/
 * (bundled fallback).
 *
 * Frames are decoded once at inSampleSize=2 to halve RAM. Drawing is just
 * a bitmap blit at a target position with optional scale + horizontal flip.
 *
 * Lifecycle:
 *   val sprite = SpriteSheet(ctx, "v160_sprites/dragon_main")
 *   sprite.load(framesPerTick = 2)
 *   // render loop:
 *   sprite.advance()
 *   sprite.drawAt(canvas, x, y, scale, flipX = false)
 *   // teardown:
 *   sprite.release()
 */
class SpriteSheet(
    private val context: Context,
    private val folder: String,
) {
    var framesPerTick: Int = 2
    var loaded: Boolean = false
        private set

    private val bitmaps = mutableListOf<Bitmap>()
    private var frameIndex = 0
    private var frameTimer = 0
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val matrix = Matrix()

    val frameCount: Int get() = bitmaps.size
    val width: Int get() = if (bitmaps.isEmpty()) 0 else bitmaps[0].width
    val height: Int get() = if (bitmaps.isEmpty()) 0 else bitmaps[0].height

    fun load(framesPerTick: Int = 2): Boolean {
        if (loaded) return true
        this.framesPerTick = framesPerTick
        try {
            val cacheDir = java.io.File(context.filesDir, "sprites/$folder")
            val fromFiles = cacheDir.isDirectory
            val fileList = if (fromFiles) {
                cacheDir.listFiles()
                    ?.filter { it.name.endsWith(".png") }
                    ?.sorted()
                    ?.map { it.name }
                    ?: emptyList()
            } else {
                context.assets.list(folder)
                    ?.filter { it.endsWith(".png") }
                    ?.sorted()
                    ?: emptyList()
            }
            if (fileList.isEmpty()) {
                Log.w("SpriteSheet", "No frames in $folder")
                return false
            }
            val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
            for (name in fileList) {
                val bmp = if (fromFiles) {
                    BitmapFactory.decodeFile("${cacheDir.absolutePath}/$name", opts)
                } else {
                    context.assets.open("$folder/$name").use {
                        BitmapFactory.decodeStream(it, null, opts)
                    }
                }
                if (bmp != null) bitmaps.add(bmp)
            }
            loaded = bitmaps.isNotEmpty()
            Log.d("SpriteSheet", "Loaded ${bitmaps.size} frames from $folder " +
                "(${if (fromFiles) "files" else "assets"}) ${width}x${height}")
            return loaded
        } catch (e: Exception) {
            Log.e("SpriteSheet", "Failed loading $folder: $e")
            return false
        }
    }

    /** Advance the animation pointer. Call once per render frame. */
    fun advance() {
        if (!loaded) return
        frameTimer++
        if (frameTimer >= framesPerTick) {
            frameTimer = 0
            frameIndex = (frameIndex + 1) % bitmaps.size
        }
    }

    /** Reset to first frame — useful when starting a one-shot cinematic. */
    fun reset() { frameIndex = 0; frameTimer = 0 }

    /** Get current normalized progress 0..1 for one-shot cinematics. */
    val progress: Float get() = if (bitmaps.isEmpty()) 0f else frameIndex.toFloat() / bitmaps.size

    /** Whether the animation has finished one full cycle since last reset. */
    val isComplete: Boolean get() = frameIndex >= bitmaps.size - 1 && frameTimer >= framesPerTick - 1

    /**
     * Draw current frame centered at (cx, cy) with given scale.
     * Honors flipX for direction-aware sprites (e.g. crow flying right vs left).
     * Optionally rotates by `rotateDeg`.
     * Optionally tints alpha (0..255).
     */
    fun drawAt(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        scale: Float = 1f,
        flipX: Boolean = false,
        rotateDeg: Float = 0f,
        alpha: Int = 255,
    ) {
        if (!loaded) return
        val bmp = bitmaps[frameIndex % bitmaps.size]
        if (bmp.isRecycled) return

        matrix.reset()
        // Center bitmap on (0,0) first
        matrix.postTranslate(-bmp.width / 2f, -bmp.height / 2f)
        if (flipX) matrix.postScale(-1f, 1f)
        if (rotateDeg != 0f) matrix.postRotate(rotateDeg)
        matrix.postScale(scale, scale)
        matrix.postTranslate(cx, cy)

        paint.alpha = alpha.coerceIn(0, 255)
        canvas.drawBitmap(bmp, matrix, paint)
        paint.alpha = 255
    }

    fun release() {
        for (b in bitmaps) if (!b.isRecycled) b.recycle()
        bitmaps.clear()
        loaded = false
        frameIndex = 0
        frameTimer = 0
    }
}
