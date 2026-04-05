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
    @Volatile private var extractionCancelled = false
    @Volatile private var isExtracting = false
    private var currentBitmap: Bitmap? = null
    private var prevBitmap: Bitmap? = null
    private var nextBitmap: Bitmap? = null
    private var crossfadeAlpha = 0f // 0 = showing current, 1 = showing next/prev
    private var targetIndex = 0
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
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
    /** Cancel any in-progress extraction */
    fun cancelExtraction() {
        extractionCancelled = true
    }

    fun extractFrames(
        videoPath: String,
        cacheDir: File,
        targetWidth: Int = 540,
        everyNthFrame: Int = 4,
        onProgress: ((current: Int, total: Int) -> Unit)? = null
    ): Boolean {
        // Cancel previous extraction if running
        extractionCancelled = true
        while (isExtracting) Thread.sleep(50) // wait for previous to stop
        extractionCancelled = false
        isExtracting = true

        try {
            val videoFile = File(videoPath)
            if (!videoFile.exists()) return false

            val videoName = videoFile.nameWithoutExtension
            framesDir = File(cacheDir, "frames_$videoName")

            // Check if frames already cached for THIS video
            val existing = framesDir!!.listFiles()?.filter { it.extension == "webp" } ?: emptyList()
            if (existing.size > 10) {
                frameCount = existing.size
                Log.d(TAG, "Frames cached: $frameCount for $videoName")
                loadFrame(0)
                isReady = true
                return true
            }

            // Clean old caches from OTHER videos, keep current
            cacheDir.listFiles()
                ?.filter { it.isDirectory && it.name.startsWith("frames_") && it.name != "frames_$videoName" }
                ?.forEach { it.deleteRecursively() }

            // Clean partial extraction if any
            framesDir!!.deleteRecursively()
            framesDir!!.mkdirs()

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
            onProgress?.invoke(0, framesToExtract)
            for (i in 0 until framesToExtract) {
                if (extractionCancelled) {
                    Log.d(TAG, "Extraction cancelled at frame $i")
                    break
                }
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
                onProgress?.invoke(extracted, framesToExtract)
            }

            retriever.release()
            System.gc()

            if (extractionCancelled) {
                isExtracting = false
                return false
            }

            frameCount = extracted
            Log.d(TAG, "Extracted $extracted frames to ${framesDir!!.path}")

            if (extracted > 0) {
                loadFrame(0)
                isReady = true
            }
            isExtracting = false
            return extracted > 0
        } catch (e: Exception) {
            Log.e(TAG, "Frame extraction failed: ${e.message}")
            isExtracting = false
            return false
        }
    }

    /**
     * Load pre-downloaded frames from a directory (no codec needed).
     * Call from any thread — no MediaMetadataRetriever involved.
     */
    fun loadFromDirectory(path: String): Boolean {
        try {
            val dir = File(path)
            if (!dir.exists()) return false

            val files = dir.listFiles()?.filter {
                it.extension == "jpg" || it.extension == "webp"
            }?.sortedBy { it.name } ?: return false

            if (files.isEmpty()) return false

            framesDir = dir
            frameCount = files.size
            loadFrame(0)
            isReady = true
            Log.d(TAG, "Loaded $frameCount frames from $path (no codec)")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "loadFromDirectory failed: ${e.message}")
            return false
        }
    }

    /** Load a frame bitmap from disk with reduced memory (RGB_565) */
    private fun loadFrameBitmap(index: Int): Bitmap? {
        if (index < 0 || index >= frameCount) return null
        val dir = framesDir ?: return null
        // Try jpg first (pre-downloaded from server), then webp (locally extracted)
        val jpgFile = File(dir, "frame_${"%04d".format(index + 1)}.jpg")
        if (jpgFile.exists()) {
            val opts = BitmapFactory.Options()
            opts.inPreferredConfig = Bitmap.Config.RGB_565
            return BitmapFactory.decodeFile(jpgFile.path, opts)
        }
        val webpFile = File(dir, "frame_${"%04d".format(index)}.webp")
        if (webpFile.exists()) {
            val opts = BitmapFactory.Options()
            opts.inPreferredConfig = Bitmap.Config.RGB_565
            return BitmapFactory.decodeFile(webpFile.path, opts)
        }
        return null
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

    private val destRect = RectF()

    /**
     * Draw current frame to canvas, scaled to fill.
     */
    fun draw(canvas: Canvas) {
        val bmp = currentBitmap ?: return
        val cw = canvas.width.toFloat()
        val ch = canvas.height.toFloat()

        val scale = maxOf(cw / bmp.width, ch / bmp.height)
        val sw = bmp.width * scale
        val sh = bmp.height * scale
        destRect.set((cw - sw) / 2f, (ch - sh) / 2f, (cw + sw) / 2f, (ch + sh) / 2f)
        canvas.drawBitmap(bmp, null, destRect, paint)
    }

    fun release() {
        extractionCancelled = true
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
