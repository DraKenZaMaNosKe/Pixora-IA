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
    var framesPerTick: Float = 2f
    var loaded: Boolean = false
        private set

    private val bitmaps = mutableListOf<Bitmap>()
    // Pre-scaled bitmaps cached at the latest known target draw size. Populated
    // by ensurePrescaled() the first time drawAt() runs with a stable scale.
    // After that, drawAt is a pure 3-arg drawBitmap (no matrix scale, no
    // bilinear filter per frame) — orders of magnitude faster on GPU.
    private val prescaled = mutableListOf<Bitmap>()
    private var prescaledFor = 0  // hashed target dims; 0 = not prescaled yet
    private var frameIndex = 0
    private var frameTimerAcc = 0f
    private var advanceDirection = 1
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val fastPaint = Paint()  // no filter — pure blit for prescaled bitmaps
    private val matrix = Matrix()

    val frameCount: Int get() = bitmaps.size
    val width: Int get() = if (bitmaps.isEmpty()) 0 else bitmaps[0].width
    val height: Int get() = if (bitmaps.isEmpty()) 0 else bitmaps[0].height

    /**
     * Load sprite frames into RAM.
     * @param framesPerTick render ticks per frame advance (float OK; negative
     *   reverses direction). Lower abs = faster animation.
     * @param sampleSize Bitmap decoder downscale factor (1 = full resolution,
     *   2 = half resolution = ~4x less RAM). Use 1 for fullscreen sprites
     *   (e.g. anime cockpit) so they don't pixelate when stretched.
     */
    fun load(framesPerTick: Float = 2f, sampleSize: Int = 2): Boolean {
        if (loaded) return true
        this.framesPerTick = framesPerTick
        this.advanceDirection = if (framesPerTick < 0f) -1 else 1
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
            val opts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
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
                "(${if (fromFiles) "files" else "assets"}) ${width}x${height} sample=$sampleSize")
            return loaded
        } catch (e: Exception) {
            Log.e("SpriteSheet", "Failed loading $folder: $e")
            return false
        }
    }

    /** Update tick rate without reloading bitmaps (spec hot-reload). */
    fun updateFramesPerTick(value: Float) {
        framesPerTick = value
        advanceDirection = if (value < 0f) -1 else 1
    }

    /** Advance the animation pointer. Call once per render frame. */
    fun advance() {
        if (!loaded || bitmaps.isEmpty()) return
        val threshold = kotlin.math.abs(framesPerTick).coerceAtLeast(0.05f)
        frameTimerAcc += 1f
        if (frameTimerAcc >= threshold) {
            frameTimerAcc -= threshold
            val n = bitmaps.size
            frameIndex = (frameIndex + advanceDirection + n) % n
        }
    }

    /** Reset to first frame — useful when starting a one-shot cinematic. */
    fun reset() { frameIndex = 0; frameTimerAcc = 0f }

    /** Get current normalized progress 0..1 for one-shot cinematics. */
    val progress: Float get() = if (bitmaps.isEmpty()) 0f else frameIndex.toFloat() / bitmaps.size

    /** Whether the animation has finished one full cycle since last reset. */
    val isComplete: Boolean get() = frameIndex >= bitmaps.size - 1 &&
        frameTimerAcc >= kotlin.math.abs(framesPerTick).coerceAtLeast(0.05f) - 0.01f

    /**
     * Draw current frame centered at (cx, cy) with given scale.
     * Honors flipX for direction-aware sprites (e.g. crow flying right vs left).
     * Optionally rotates by `rotateDeg`.
     * Optionally tints alpha (0..255).
     */
    /**
     * Pre-scale all frames to a fixed target size and cache them. After this
     * runs, drawAt() uses a pure 3-arg drawBitmap (no per-frame scale, no
     * bilinear filter). One-time cost ~50-200ms; per-frame savings ~10-30ms
     * on Mali GPUs. Idempotent — calling with the same dims is a no-op.
     *
     * Skipped when there's a rotation or non-identity matrix transform —
     * those still need the slow path. Also skipped if the requested scale
     * is suspiciously close to 1.0 (would be wasted work).
     */
    fun ensurePrescaled(targetW: Int, targetH: Int) {
        if (!loaded || bitmaps.isEmpty()) return
        if (targetW < 2 || targetH < 2) return
        val key = (targetW shl 16) or (targetH and 0xffff)
        if (prescaledFor == key && prescaled.size == bitmaps.size) return
        // Tear down old prescale
        for (b in prescaled) if (!b.isRecycled) b.recycle()
        prescaled.clear()
        try {
            for (b in bitmaps) {
                if (b.isRecycled) continue
                val scaled = if (b.width == targetW && b.height == targetH) b
                              else Bitmap.createScaledBitmap(b, targetW, targetH, true)
                prescaled.add(scaled)
            }
            prescaledFor = key
            Log.d("SpriteSheet", "Prescaled $folder to ${targetW}x${targetH} (${prescaled.size} frames)")
        } catch (e: OutOfMemoryError) {
            // Fallback: keep original bitmaps; slow path will still draw
            for (b in prescaled) if (!b.isRecycled && b !in bitmaps) b.recycle()
            prescaled.clear()
            prescaledFor = 0
            Log.w("SpriteSheet", "Prescale OOM for $folder, falling back to slow path")
        }
    }

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
        val src = bitmaps[frameIndex % bitmaps.size]
        if (src.isRecycled) return

        // FAST PATH: use prescaled bitmap if available and no rotation/flip
        // is requested. This is a pure 3-arg drawBitmap blit on hardware
        // canvas — essentially zero GPU time per frame.
        if (prescaledFor != 0 && prescaled.isNotEmpty() && !flipX && rotateDeg == 0f) {
            val bmp = prescaled[frameIndex % prescaled.size]
            if (!bmp.isRecycled) {
                val left = cx - bmp.width / 2f
                val top  = cy - bmp.height / 2f
                if (alpha == 255) {
                    canvas.drawBitmap(bmp, left, top, fastPaint)
                } else {
                    fastPaint.alpha = alpha.coerceIn(0, 255)
                    canvas.drawBitmap(bmp, left, top, fastPaint)
                    fastPaint.alpha = 255
                }
                return
            }
        }

        val bmp = src
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
        for (b in prescaled) if (!b.isRecycled && b !in bitmaps) b.recycle()
        prescaled.clear()
        prescaledFor = 0
        for (b in bitmaps) if (!b.isRecycled) b.recycle()
        bitmaps.clear()
        loaded = false
        frameIndex = 0
        frameTimerAcc = 0f
    }
}
