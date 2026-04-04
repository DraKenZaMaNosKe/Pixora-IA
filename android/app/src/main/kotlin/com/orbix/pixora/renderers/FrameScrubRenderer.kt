package com.orbix.pixora.renderers

import android.graphics.*
import android.media.MediaMetadataRetriever
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * Extracts frames from a video and renders them on Canvas with crossfade.
 * Only keeps 3 bitmaps in RAM at a time (previous, current, next).
 * Frames stored as WebP files on disk.
 */
class FrameScrubRenderer {

    private var framesDir: File? = null
    private var frameCount = 0
    private var currentIndex = 0
    private var currentBitmap: Bitmap? = null
    private var prevBitmap: Bitmap? = null
    private var nextBitmap: Bitmap? = null
    private var crossfadeAlpha = 0f // 0 = showing current, 1 = showing next/prev
    private var targetIndex = 0
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val fadePaint = Paint(Paint.FILTER_BITMAP_FLAG)
    var isReady = false
        private set

    /**
     * Extract frames from video file. Call from background thread.
     * @param videoPath path to mp4 file
     * @param cacheDir app cache directory
     * @param targetWidth scale frames to this width (0 = original)
     * @param everyNthFrame extract every Nth frame (4 = ~9fps from 24fps video)
     * @return true if extraction succeeded
     */
    fun extractFrames(
        videoPath: String,
        cacheDir: File,
        targetWidth: Int = 540,
        everyNthFrame: Int = 4
    ): Boolean {
        try {
            val videoFile = File(videoPath)
            if (!videoFile.exists()) return false

            // Create frames directory based on video filename
            val videoName = videoFile.nameWithoutExtension
            framesDir = File(cacheDir, "frames_$videoName")
            framesDir!!.mkdirs()

            // Check if already extracted
            val existing = framesDir!!.listFiles()?.filter { it.extension == "webp" } ?: emptyList()
            if (existing.size > 10) {
                frameCount = existing.size
                Log.d(TAG, "Frames already extracted: $frameCount")
                loadFrame(0)
                isReady = true
                return true
            }

            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)

            val durationMs = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: return false

            // Calculate frame times
            val fps = 24 // assume 24fps
            val totalFrames = (durationMs * fps / 1000).toInt()
            val framesToExtract = totalFrames / everyNthFrame

            Log.d(TAG, "Extracting $framesToExtract frames from ${durationMs}ms video")

            var extracted = 0
            for (i in 0 until framesToExtract) {
                val timeUs = (i * everyNthFrame * 1000000L / fps)
                val frame = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                    ?: continue

                // Scale down
                val scaled = if (targetWidth > 0 && frame.width > targetWidth) {
                    val ratio = targetWidth.toFloat() / frame.width
                    val h = (frame.height * ratio).toInt()
                    Bitmap.createScaledBitmap(frame, targetWidth, h, true).also {
                        if (it != frame) frame.recycle()
                    }
                } else {
                    frame
                }

                // Save as WebP
                val outFile = File(framesDir, "frame_${"%04d".format(i)}.webp")
                FileOutputStream(outFile).use { fos ->
                    scaled.compress(Bitmap.CompressFormat.WEBP, 80, fos)
                }
                scaled.recycle()
                extracted++
            }

            retriever.release()
            frameCount = extracted
            Log.d(TAG, "Extracted $extracted frames to ${framesDir!!.path}")

            if (extracted > 0) {
                loadFrame(0)
                isReady = true
            }
            return extracted > 0
        } catch (e: Exception) {
            Log.e(TAG, "Frame extraction failed: ${e.message}")
            return false
        }
    }

    /** Load a frame bitmap from disk with reduced memory (RGB_565) */
    private fun loadFrameBitmap(index: Int): Bitmap? {
        if (index < 0 || index >= frameCount) return null
        val dir = framesDir ?: return null
        val file = File(dir, "frame_${"%04d".format(index)}.webp")
        if (!file.exists()) return null
        val opts = BitmapFactory.Options()
        opts.inPreferredConfig = Bitmap.Config.RGB_565 // 2 bytes/pixel instead of 4
        return BitmapFactory.decodeFile(file.path, opts)
    }

    /** Load frame and its neighbors into RAM */
    private fun loadFrame(index: Int) {
        val safeIndex = index.coerceIn(0, frameCount - 1)
        if (safeIndex == currentIndex && currentBitmap != null) return

        // Recycle old bitmaps
        if (safeIndex != currentIndex - 1) prevBitmap?.recycle()
        if (safeIndex != currentIndex + 1) nextBitmap?.recycle()

        // Shift or load fresh
        when {
            safeIndex == currentIndex + 1 -> {
                prevBitmap?.recycle()
                prevBitmap = currentBitmap
                currentBitmap = nextBitmap
                nextBitmap = loadFrameBitmap(safeIndex + 1)
            }
            safeIndex == currentIndex - 1 -> {
                nextBitmap?.recycle()
                nextBitmap = currentBitmap
                currentBitmap = prevBitmap
                prevBitmap = loadFrameBitmap(safeIndex - 1)
            }
            else -> {
                prevBitmap?.recycle()
                currentBitmap?.recycle()
                nextBitmap?.recycle()
                prevBitmap = loadFrameBitmap(safeIndex - 1)
                currentBitmap = loadFrameBitmap(safeIndex)
                nextBitmap = loadFrameBitmap(safeIndex + 1)
            }
        }
        currentIndex = safeIndex
    }

    /**
     * Set target frame based on touch position (0.0 to 1.0).
     * Animates smoothly to target.
     */
    fun seekTo(fraction: Float) {
        if (frameCount <= 0) return
        targetIndex = (fraction * (frameCount - 1)).toInt().coerceIn(0, frameCount - 1)
    }

    /**
     * Update animation state. Call every frame (~16ms).
     * Returns true if a redraw is needed.
     */
    fun update(): Boolean {
        if (!isReady || frameCount <= 0) return false

        if (currentIndex != targetIndex) {
            // Move one step toward target
            val step = if (targetIndex > currentIndex) 1 else -1
            loadFrame(currentIndex + step)
            return true
        }
        return false
    }

    /**
     * Draw current frame to canvas, scaled to fill.
     */
    fun draw(canvas: Canvas) {
        val bmp = currentBitmap ?: return

        // Scale to fill canvas
        val canvasW = canvas.width.toFloat()
        val canvasH = canvas.height.toFloat()
        val bmpW = bmp.width.toFloat()
        val bmpH = bmp.height.toFloat()

        val scale = maxOf(canvasW / bmpW, canvasH / bmpH)
        val scaledW = bmpW * scale
        val scaledH = bmpH * scale
        val left = (canvasW - scaledW) / 2f
        val top = (canvasH - scaledH) / 2f

        val dest = RectF(left, top, left + scaledW, top + scaledH)
        canvas.drawBitmap(bmp, null, dest, paint)
    }

    fun release() {
        prevBitmap?.recycle()
        currentBitmap?.recycle()
        nextBitmap?.recycle()
        prevBitmap = null
        currentBitmap = null
        nextBitmap = null
        isReady = false
        frameCount = 0
    }

    /** Delete old frame caches, keeping only the current video's frames */
    fun cleanOldCaches(cacheDir: File) {
        try {
            val currentDirName = framesDir?.name ?: return
            cacheDir.listFiles()
                ?.filter { it.isDirectory && it.name.startsWith("frames_") && it.name != currentDirName }
                ?.forEach { dir ->
                    dir.deleteRecursively()
                    Log.d(TAG, "Cleaned old cache: ${dir.name}")
                }
        } catch (e: Exception) {
            Log.e(TAG, "Cache cleanup failed: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "FrameScrub"
    }
}
