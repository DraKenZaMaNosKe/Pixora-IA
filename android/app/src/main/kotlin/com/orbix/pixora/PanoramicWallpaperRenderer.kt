package com.orbix.pixora

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import kotlin.math.abs

/**
 * Renders a bitmap as a wallpaper that auto-detects "panoramic" (wide ratio,
 * scrolls horizontally with launcher offset) vs "standard" (center-cropped
 * to fit screen, no scroll). Designed to plug into any Android
 * WallpaperService.Engine.
 *
 * Single responsibility: load + scale + draw + scroll a bitmap. No knowledge
 * of overlays, video, audio, scenes, or any other capability — those are the
 * orchestrator's job to compose on top.
 *
 * Threading model: public methods are safe to call from the main thread.
 * Bitmap decode and scaling happen on a background Thread to avoid blocking.
 * Drawing should be called on the rendering thread (typically main).
 *
 * Lifecycle:
 *   1. Construct once per WallpaperService.Engine.
 *   2. Call onSurfaceChanged(w, h) whenever the surface size changes.
 *   3. Call loadFromFile(path) to load a new bitmap.
 *   4. Call onOffsetsChanged(xOffset) when the launcher reports scroll changes.
 *   5. Call drawOn(canvas) inside your draw loop.
 *   6. Call release() in onDestroy to free bitmap memory.
 *
 * Example usage in a standalone WallpaperService:
 *
 *   class MyWallpaperService : WallpaperService() {
 *       inner class MyEngine : Engine() {
 *           private val pano = PanoramicWallpaperRenderer(applicationContext)
 *
 *           override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {
 *               pano.onSurfaceChanged(w, h)
 *               pano.loadFromFile(currentPath) { drawNextFrame() }
 *           }
 *           override fun onOffsetsChanged(xOffset: Float, yOffset: Float,
 *                                         xStep: Float, yStep: Float,
 *                                         xPixelOffset: Int, yPixelOffset: Int) {
 *               pano.onOffsetsChanged(xOffset)
 *               drawNextFrame()
 *           }
 *           override fun onDestroy() { pano.release() }
 *
 *           private fun drawNextFrame() {
 *               val canvas = surfaceHolder.lockCanvas() ?: return
 *               pano.drawOn(canvas)
 *               surfaceHolder.unlockCanvasAndPost(canvas)
 *           }
 *       }
 *       override fun onCreateEngine() = MyEngine()
 *   }
 *
 * Performance characteristics (see commits 45b2583, fbf8e57 for the journey):
 * - Decode runs at most once per (path, surface_dims) combination — idempotent.
 * - Scaling runs at most once per (path, surface_dims) combination — idempotent.
 * - Burst calls (3 in 150ms from the typical onSurfaceChanged + onVisibilityChanged
 *   + debounced prefs reload pattern) are coalesced to a single Thread spawn.
 * - On Samsung A15 / panoramic 4128x1024: ~80-130ms decode + ~700ms scale.
 */
class PanoramicWallpaperRenderer(private val context: Context) {

    companion object {
        private const val TAG = "PanoramicWP"

        // Aspect ratio threshold to treat a bitmap as panoramic. A 16:9 phone
        // screen has dstRatio ≈ 0.46 portrait. A 4128x1024 wallpaper has
        // srcRatio = 4.03, which is > 0.46 * 1.5 = 0.69 — so it qualifies.
        // The 1.5x multiplier filters out merely-wider-than-screen images
        // (e.g., a 1920x1080 landscape on a portrait phone) from triggering
        // the full panoramic scroll machinery.
        private const val PANORAMIC_RATIO_MULTIPLIER = 1.5f
    }

    private val handler = Handler(Looper.getMainLooper())
    private val bitmapLock = Object()

    // Source bitmap (decoded from file, not yet scaled to surface dims)
    private var sourceBitmap: Bitmap? = null

    // Scaled bitmap ready to draw — one of these is non-null at a time
    @Volatile private var scaledBitmap: Bitmap? = null
    @Volatile private var panoramicBitmap: Bitmap? = null

    @Volatile var isPanoramic = false
        private set

    private var surfaceWidth = 0
    private var surfaceHeight = 0

    // Scroll state (only relevant when isPanoramic).
    //  - scrollOffsetPx: current draw position, interpolated each frame.
    //  - targetScrollPx: where we WANT to be (latest launcher offset).
    //  - The renderer interpolates scrollOffsetPx → targetScrollPx in [tick]
    //    so swipes look smooth even when Samsung emits sparse events
    //    (typically 1-2 events per gesture, not every frame).
    private var scrollOffsetPx = 0f
    private var targetScrollPx = 0f

    // Latest xOffset reported by the launcher. Retained across state changes
    // so that when the scaling Thread finally produces a panoramic bitmap,
    // we re-apply this offset — otherwise the first launcher event (which
    // Samsung emits ~800ms BEFORE our bg scaling completes on initial engine
    // attach) is lost and the wallpaper stays at offset=0 until the next swipe.
    @Volatile private var lastXOffset: Float = 0f

    /** Interpolation factor per tick — higher = faster snap, lower = smoother glide. */
    private val lerpFactor = 0.18f

    /** Threshold below which we stop animating (1px = imperceptible). */
    private val settleThresholdPx = 1f

    val scrollRangePx: Int
        get() = (panoramicBitmap?.width ?: 0) - surfaceWidth

    // Idempotency guards — see commits 45b2583 + fbf8e57 for full context.
    @Volatile private var lastDecodedPath: String? = null
    @Volatile private var lastDecodedSurfaceW: Int = 0
    @Volatile private var lastDecodedSurfaceH: Int = 0
    @Volatile private var lastScaledForPath: String? = null
    @Volatile private var lastScaledSurfaceW: Int = 0
    @Volatile private var lastScaledSurfaceH: Int = 0
    @Volatile private var scaleVersion = 0

    private val paint = Paint().apply { isFilterBitmap = true }

    // ────────────────────────────────────────────────────────────────────────
    // Public API
    // ────────────────────────────────────────────────────────────────────────

    /**
     * Notify the renderer of a new surface size. Call from
     * WallpaperService.Engine.onSurfaceChanged().
     */
    fun onSurfaceChanged(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        val dimensionsChanged = surfaceWidth != width || surfaceHeight != height
        surfaceWidth = width
        surfaceHeight = height
        if (dimensionsChanged) {
            // Surface changed → force re-scale of current bitmap if we have one.
            // The guard will skip if dims happen to match the last scale.
            createScaledBitmap()
        }
    }

    /**
     * Load a bitmap from disk and prepare it for rendering. Safe to call
     * multiple times with the same path — only decodes/scales when the inputs
     * actually changed since the last successful operation.
     *
     * The onReady callback fires when the new bitmap is ready to draw (after
     * the bg scaling Thread completes). It's optional — callers that always
     * draw on a vsync schedule can ignore it.
     */
    fun loadFromFile(path: String, onReady: () -> Unit = {}) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) {
            Log.d(TAG, "loadFromFile: surface not ready (${surfaceWidth}x${surfaceHeight}), deferring")
            return
        }

        // Idempotency guard: same path + same surface + bitmap still alive → skip.
        val existing = sourceBitmap
        if (path == lastDecodedPath &&
            surfaceWidth == lastDecodedSurfaceW &&
            surfaceHeight == lastDecodedSurfaceH &&
            existing != null && !existing.isRecycled
        ) {
            Log.d(TAG, "loadFromFile: bitmap already current ($path @ ${surfaceWidth}x${surfaceHeight}), skipping decode")
            return
        }

        val file = File(path)
        if (!file.exists()) {
            Log.e(TAG, "loadFromFile: FILE NOT FOUND at $path")
            return
        }

        // Probe dimensions
        val opts = BitmapFactory.Options()
        opts.inJustDecodeBounds = true
        BitmapFactory.decodeFile(path, opts)
        if (opts.outWidth <= 0 || opts.outHeight <= 0) {
            Log.e(TAG, "loadFromFile: invalid dimensions ${opts.outWidth}x${opts.outHeight}")
            return
        }

        opts.inSampleSize = calculateInSampleSize(opts, opts.outWidth, surfaceHeight)
        opts.inJustDecodeBounds = false
        opts.inPreferredConfig = Bitmap.Config.RGB_565

        val decoded = try {
            BitmapFactory.decodeFile(path, opts)
        } catch (oom: OutOfMemoryError) {
            Log.e(TAG, "OOM decoding, retrying with higher sample: ${oom.message}")
            opts.inSampleSize *= 2
            BitmapFactory.decodeFile(path, opts)
        } ?: run {
            Log.e(TAG, "Failed to decode bitmap: $path (sampleSize=${opts.inSampleSize})")
            return
        }

        // Recycle previous source if it was replaced without going through
        // the scaling reassignment path (consecutive reloads stacking up).
        sourceBitmap?.takeIf { it !== decoded && !it.isRecycled }?.recycle()
        sourceBitmap = decoded
        lastDecodedPath = path
        lastDecodedSurfaceW = surfaceWidth
        lastDecodedSurfaceH = surfaceHeight
        Log.d(TAG, "Bitmap decoded OK: ${decoded.width}x${decoded.height} config=${decoded.config}")

        // Trigger the scaling pass; onReady will be invoked when it completes.
        createScaledBitmap(onReady)
    }

    /**
     * Update the horizontal scroll offset from the launcher. xOffset is
     * normalized [0..1] across home-screen pages.
     */
    fun onOffsetsChanged(xOffset: Float) {
        // Retain the offset even if bitmap isn't ready yet — applyScrollOffset()
        // re-reads this when the scaling Thread completes.
        lastXOffset = xOffset.coerceIn(0f, 1f)
        applyScrollOffset()
    }

    /**
     * Recompute targetScrollPx from lastXOffset. Safe to call any time:
     * no-ops if no panoramic bitmap is ready yet.
     * Sets the TARGET, not the current position — interpolation handles
     * the smooth glide via [tick] on the orchestrator's draw loop.
     */
    private fun applyScrollOffset() {
        if (!isPanoramic) return
        val range = scrollRangePx
        if (range <= 0) return
        targetScrollPx = lastXOffset * range
    }

    /**
     * Like [applyScrollOffset] but ALSO snaps scrollOffsetPx to the target
     * immediately — used when a new bitmap was just loaded so the first
     * paint lands at the correct position instead of animating from 0.
     */
    private fun syncScrollOffsetImmediate() {
        if (!isPanoramic) return
        val range = scrollRangePx
        if (range <= 0) return
        targetScrollPx = lastXOffset * range
        scrollOffsetPx = targetScrollPx
    }

    /**
     * Advance scroll interpolation one frame. Call from the orchestrator's
     * draw loop (typically every ~16ms while [isSettling] returns true).
     * Returns true if the position changed enough to warrant a redraw.
     */
    fun tick(): Boolean {
        val delta = targetScrollPx - scrollOffsetPx
        if (kotlin.math.abs(delta) < settleThresholdPx) {
            if (scrollOffsetPx != targetScrollPx) {
                scrollOffsetPx = targetScrollPx
                return true
            }
            return false
        }
        scrollOffsetPx += delta * lerpFactor
        return true
    }

    /** True when scrollOffsetPx hasn't yet caught up to targetScrollPx. */
    fun isSettling(): Boolean =
        isPanoramic && kotlin.math.abs(targetScrollPx - scrollOffsetPx) >= settleThresholdPx

    /**
     * Draw the current bitmap onto the canvas. Returns true if a bitmap was
     * actually drawn, false if nothing is ready yet (caller may want to
     * fill the canvas with a fallback color in that case).
     */
    fun drawOn(canvas: Canvas): Boolean {
        synchronized(bitmapLock) {
            val pan = panoramicBitmap
            if (pan != null && !pan.isRecycled) {
                Log.d(TAG, "drawOn panoramic: bmp=${pan.width}x${pan.height} offsetPx=$scrollOffsetPx canvas=${canvas.width}x${canvas.height}")
                canvas.drawBitmap(pan, -scrollOffsetPx, 0f, paint)
                return true
            }
            val std = scaledBitmap
            if (std != null && !std.isRecycled) {
                Log.d(TAG, "drawOn standard: bmp=${std.width}x${std.height}")
                canvas.drawBitmap(std, 0f, 0f, paint)
                return true
            }
            Log.w(TAG, "drawOn: no bitmap ready")
        }
        return false
    }

    /**
     * Free all bitmap memory. Call from WallpaperService.Engine.onDestroy().
     * After calling, the renderer is unusable until loadFromFile() runs again
     * (which will only succeed after onSurfaceChanged() restores dims).
     */
    fun release() {
        synchronized(bitmapLock) {
            sourceBitmap?.recycle()
            scaledBitmap?.recycle()
            panoramicBitmap?.recycle()
            sourceBitmap = null
            scaledBitmap = null
            panoramicBitmap = null
        }
        lastDecodedPath = null
        lastDecodedSurfaceW = 0
        lastDecodedSurfaceH = 0
        lastScaledForPath = null
        lastScaledSurfaceW = 0
        lastScaledSurfaceH = 0
        surfaceWidth = 0
        surfaceHeight = 0
        isPanoramic = false
        scrollOffsetPx = 0f
        targetScrollPx = 0f
        lastXOffset = 0f
    }

    // ────────────────────────────────────────────────────────────────────────
    // Internal
    // ────────────────────────────────────────────────────────────────────────

    private fun createScaledBitmap(onReady: () -> Unit = {}) {
        val bmp = sourceBitmap ?: return
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        // Idempotency guard — see commit fbf8e57 for why this is synchronous.
        val currentPath = lastDecodedPath
        if (currentPath != null &&
            currentPath == lastScaledForPath &&
            surfaceWidth == lastScaledSurfaceW &&
            surfaceHeight == lastScaledSurfaceH
        ) {
            Log.d(TAG, "createScaledBitmap: already current ($currentPath @ ${surfaceWidth}x${surfaceHeight}), skipping")
            handler.post { onReady() }
            return
        }

        val myVersion = ++scaleVersion
        val targetW = surfaceWidth
        val targetH = surfaceHeight

        // Register in-flight scaling synchronously so subsequent burst calls
        // hit the guard above and skip.
        lastScaledForPath = currentPath
        lastScaledSurfaceW = targetW
        lastScaledSurfaceH = targetH

        Thread {
            try {
                val srcRatio = bmp.width.toFloat() / bmp.height.toFloat()
                val dstRatio = targetW.toFloat() / targetH.toFloat()
                val panoramic = srcRatio > dstRatio * PANORAMIC_RATIO_MULTIPLIER

                if (panoramic) {
                    val scaledHeight = targetH
                    val scaledWidth = (bmp.width.toFloat() / bmp.height.toFloat() * scaledHeight).toInt()
                    val newPanBmp = Bitmap.createScaledBitmap(bmp, scaledWidth, scaledHeight, true)
                    if (myVersion == scaleVersion) {
                        synchronized(bitmapLock) {
                            val oldScaled = scaledBitmap
                            val oldPan = panoramicBitmap
                            if (sourceBitmap === bmp) sourceBitmap = null
                            scaledBitmap = null
                            panoramicBitmap = newPanBmp
                            isPanoramic = true
                            oldScaled?.recycle()
                            oldPan?.recycle()
                        }
                        // Re-apply the last launcher offset now that we have a
                        // valid range — fixes the race where Samsung emits
                        // onOffsetsChanged BEFORE this Thread completes.
                        // Use immediate sync so the first paint lands at the
                        // right spot instead of animating from 0.
                        syncScrollOffsetImmediate()
                        bmp.recycle()
                        Log.d(TAG, "Panoramic: ${scaledWidth}x${scaledHeight} (scroll range: ${scaledWidth - targetW}px) syncedOffset=$lastXOffset → ${scrollOffsetPx}px")
                    } else {
                        newPanBmp.recycle()
                        bmp.recycle()
                    }
                } else {
                    val (cropW, cropH) = if (srcRatio > dstRatio) {
                        Pair((bmp.height * dstRatio).toInt(), bmp.height)
                    } else {
                        Pair(bmp.width, (bmp.width / dstRatio).toInt())
                    }
                    val x = (bmp.width - cropW) / 2
                    val y = (bmp.height - cropH) / 2
                    val cropped = Bitmap.createBitmap(bmp, x, y, cropW, cropH)
                    val scaled = Bitmap.createScaledBitmap(cropped, targetW, targetH, true)
                    if (cropped !== scaled && cropped !== bmp) cropped.recycle()

                    if (myVersion == scaleVersion) {
                        synchronized(bitmapLock) {
                            val oldScaled = scaledBitmap
                            val oldPan = panoramicBitmap
                            if (sourceBitmap === bmp) sourceBitmap = null
                            panoramicBitmap = null
                            scaledBitmap = scaled
                            isPanoramic = false
                            if (oldScaled !== scaled) oldScaled?.recycle()
                            if (oldPan !== scaled) oldPan?.recycle()
                        }
                        if (bmp !== scaled && bmp !== cropped) bmp.recycle()
                        Log.d(TAG, "Scaled: ${targetW}x${targetH} (v$myVersion)")
                    } else {
                        if (scaled !== bmp && scaled !== cropped) scaled.recycle()
                        if (cropped !== bmp) cropped.recycle()
                        bmp.recycle()
                    }
                }
                handler.post { onReady() }
            } catch (e: Exception) {
                Log.e(TAG, "createScaledBitmap error: ${e.message}")
            }
        }.start()
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val height = options.outHeight
        val width = options.outWidth
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            val halfH = height / 2
            val halfW = width / 2
            while ((halfH / inSampleSize) >= reqHeight && (halfW / inSampleSize) >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }
}
