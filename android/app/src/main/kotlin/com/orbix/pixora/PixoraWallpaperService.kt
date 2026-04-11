package com.orbix.pixora

import android.app.KeyguardManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.*
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.util.Log
import android.view.MotionEvent
import android.view.SurfaceHolder
import com.orbix.pixora.renderers.*
import java.io.File
import kotlin.math.abs

class PixoraWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = PixoraEngine()

    inner class PixoraEngine : Engine(), EqualizerRenderer.AudioCallback {
        private val handler = Handler(Looper.getMainLooper())
        private var wallpaperBitmap: Bitmap? = null
        @Volatile private var scaledBitmap: Bitmap? = null
        private val glowDots = mutableListOf<GlowDot>()
        @Volatile private var drawing = false
        private var surfaceWidth = 0
        private var surfaceHeight = 0
        private var glowColor = Color.parseColor("#7C4DFF")

        // Panoramic scroll
        private var isPanoramic = false
        @Volatile private var panoramicBitmap: Bitmap? = null
        private var touchStartX = 0f
        private var scrollOffsetPx = 0f
        private var targetScrollPx = 0f
        private var scrollVelocity = 0f

        // Animation
        private var animationPhase = 0f
        private var idleMode = false
        private var isRainWallpaper = false
        private var currentWallpaperPath: String? = null

        // Video wallpaper (MediaPlayer for Auto Play — no codec conflicts)
        private var mediaPlayer: MediaPlayer? = null
        @Volatile private var isVideoWallpaper = false
        private var isInteractive = false // touch scrubbing mode

        // Frame scrub mode: extracted frames rendered via Canvas
        private val frameScrubRenderer = FrameScrubRenderer()
        private var isFrameMode = false // true when interactive uses extracted frames
        private val frameScrubUpdateRunnable = object : Runnable {
            override fun run() {
                if (!isFrameMode || !frameScrubRenderer.isReady) return
                if (frameScrubRenderer.update()) {
                    drawFrame()
                    // Only keep running if animation is active (seeking to target)
                    handler.postDelayed(this, 30)
                }
                // If update() returns false (no movement), stop loop — saves CPU
                // Will be restarted on next touch event
            }
        }

        // Lock for bitmap field access across threads
        private val bitmapLock = Object()

        // Lock for ExoPlayer start/stop synchronization
        private val videoLock = Object()

        // Video loop fade: darkens near end, brightens at start
        // NOTE: Fade overlay was REMOVED. It used Canvas drawing on the SAME Surface
        // where MediaPlayer renders the video, which corrupted the surface producer state
        // and caused setVideoSurfaceTexture to fail with -22 on the next video install.
        // Canvas (CPU producer) and MediaPlayer (hardware producer) cannot share a Surface.
        // For loop fade-in/out, bake it into the video file with ffmpeg:
        //   ffmpeg -i in.mp4 -vf "fade=in:0:12,fade=out:st=4.5:d=0.5" out.mp4
        private var cachedDuration = 0L

        // Pre-allocated paint for glow dots
        private val glowDotPaint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Renderers
        private val clockRenderer = ClockRenderer()
        private val equalizerRenderer = EqualizerRenderer(applicationContext)
        private val rainRenderer = RainEffectRenderer()
        private val batteryIndicator = BatteryIndicator(applicationContext)
        private val systemRings = SystemRingsRenderer(applicationContext)
        private val captionOverlay = CaptionOverlay()

        // Auto-rotate: listen for wallpaper path changes from AutoRotateWorker
        private var prefsListener: SharedPreferences.OnSharedPreferenceChangeListener? = null

        private val drawRunnable = object : Runnable {
            override fun run() {
                if (drawing) {
                    drawFrame()
                    // In frame mode (Explore), use slow refresh — only clock needs updating
                    val delay = when {
                        isFrameMode -> IDLE_FRAME_DELAY // 1fps — clock updates every second
                        idleMode -> IDLE_FRAME_DELAY
                        else -> FRAME_DELAY
                    }
                    handler.postDelayed(this, delay)
                }
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder?) {
            super.onCreate(surfaceHolder)
            setTouchEventsEnabled(true)
            equalizerRenderer.audioCallback = this
            loadWallpaperImage()
            batteryIndicator.registerBatteryReceiver()
            registerPrefsListener()
            Log.d(TAG, "Engine onCreate")
        }

        // EqualizerRenderer.AudioCallback
        override fun onAudioStarted() {
            if (!drawing) {
                equalizerRenderer.silentFrames = 0
                drawing = true
                handler.post(drawRunnable)
            }
        }

        @Volatile private var pendingReload: Runnable? = null

        private fun registerPrefsListener() {
            val prefs = applicationContext.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
            prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                if (key == "changed_at" || key == "wallpaper_path") {
                    Log.d(TAG, "Prefs changed: $key — scheduling reload")
                    // Debounce: only reload once after 300ms of no changes
                    pendingReload?.let { handler.removeCallbacks(it) }
                    val reload = Runnable {
                        Log.d(TAG, "Executing debounced reload")
                        loadWallpaperImage()
                        if (!isVideoWallpaper) createScaledBitmap()
                    }
                    pendingReload = reload
                    handler.postDelayed(reload, 300)
                }
            }
            prefs.registerOnSharedPreferenceChangeListener(prefsListener)
        }

        private fun unregisterPrefsListener() {
            prefsListener?.let {
                val prefs = applicationContext.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
                prefs.unregisterOnSharedPreferenceChangeListener(it)
            }
            prefsListener = null
        }

        private fun loadWallpaperImage() {
            try {
                val prefs = applicationContext.getSharedPreferences("pixora_live", 0)
                val path = prefs.getString("wallpaper_path", null)
                val color = prefs.getString("glow_color", "#7C4DFF")
                val caption = prefs.getString("caption", null)
                isInteractive = prefs.getBoolean("interactive", false)

                // Update caption: show immediately on change, then cycle every 3 min
                if (caption != captionOverlay.currentCaption) {
                    captionOverlay.currentCaption = caption
                    val now = System.currentTimeMillis()
                    captionOverlay.lastCaptionChange = now
                    captionOverlay.lastCaptionShowTime = now
                }

                color?.let {
                    try { glowColor = Color.parseColor(it) } catch (_: Exception) {}
                }

                // Pick clock style based on wallpaper path hash
                clockRenderer.clockStyle = abs((path ?: "").hashCode()) % 4
                currentWallpaperPath = path
                isRainWallpaper = path?.contains("lofi_girl_rain") == true

                if (path != null) {
                    val file = File(path)
                    Log.d(TAG, "loadWallpaperImage: path=$path exists=${file.exists()} len=${if(file.exists()) file.length() else -1}")
                    if (file.exists()) {
                        // Frames directory: pre-downloaded images for Explore mode
                        if (file.isDirectory) {
                            isInteractive = true
                            isVideoWallpaper = true
                            startVideoWallpaper(path)
                            return
                        }

                        val isVideo = path.endsWith(".mp4", ignoreCase = true) ||
                            path.endsWith(".webm", ignoreCase = true)

                        if (isVideo) {
                            startVideoWallpaper(path)
                            return
                        }

                        // Stop video/shader if switching to image
                        stopVideoWallpaper()
                        // (shaders use separate service)

                        val opts = BitmapFactory.Options()
                        opts.inJustDecodeBounds = true
                        BitmapFactory.decodeFile(path, opts)
                        Log.d(TAG, "decodeFile bounds: ${opts.outWidth}x${opts.outHeight} mimeType=${opts.outMimeType}")

                        if (opts.outWidth <= 0 || opts.outHeight <= 0) {
                            Log.e(TAG, "Invalid bitmap dimensions: ${opts.outWidth}x${opts.outHeight}")
                            return
                        }

                        // Use actual surface height, or screen height as fallback
                        val targetH = if (surfaceHeight > 0) surfaceHeight else
                            resources.displayMetrics.heightPixels
                        opts.inSampleSize = calculateInSampleSize(opts, opts.outWidth, targetH)
                        opts.inJustDecodeBounds = false
                        opts.inPreferredConfig = Bitmap.Config.RGB_565

                        val decoded = try {
                            BitmapFactory.decodeFile(path, opts)
                        } catch (oom: OutOfMemoryError) {
                            Log.e(TAG, "OOM decoding bitmap, retrying with higher sample: ${oom.message}")
                            opts.inSampleSize *= 2
                            BitmapFactory.decodeFile(path, opts)
                        }

                        if (decoded != null) {
                            wallpaperBitmap = decoded
                            Log.d(TAG, "Bitmap decoded OK: ${decoded.width}x${decoded.height} config=${decoded.config}")
                        } else {
                            Log.e(TAG, "Failed to decode bitmap: $path (sampleSize=${opts.inSampleSize})")
                        }
                    } else {
                        Log.e(TAG, "loadWallpaperImage: FILE NOT FOUND at $path")
                    }
                } else {
                    Log.w(TAG, "loadWallpaperImage: path is null in SharedPreferences")
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadWallpaperImage error: ${e.message}")
            }
        }

        // Guard against multiple simultaneous video starts
        @Volatile private var videoStarting = false

        private var videoRetryCount = 0
        private val MAX_VIDEO_RETRIES = 10

        private fun startVideoWallpaper(path: String) {
            synchronized(videoLock) {
                if (videoStarting) return
                videoStarting = true
            }
            Log.d(TAG, "Starting video: $path")

            // Stop canvas drawing
            drawing = false
            handler.removeCallbacks(drawRunnable)
            equalizerRenderer.releaseVisualizer()
            synchronized(bitmapLock) {
                scaledBitmap = null
                panoramicBitmap = null
                wallpaperBitmap = null
            }

            stopVideoWallpaper()
            isVideoWallpaper = true

            // Explore mode: load pre-downloaded frames (no codec needed)
            if (isInteractive) {
                if (isFrameMode) {
                    synchronized(videoLock) { videoStarting = false }
                    return
                }
                isFrameMode = true
                synchronized(videoLock) { videoStarting = false }

                val pathFile = File(path)
                if (pathFile.isDirectory) {
                    Log.d(TAG, "Explore: loading frames from $path")
                    if (frameScrubRenderer.loadFromDirectory(path)) {
                        drawing = true
                        handler.post(drawRunnable)
                        handler.post(frameScrubUpdateRunnable)
                    } else {
                        isFrameMode = false
                    }
                }
                return
            }

            // Auto Play: use MediaPlayer — wait for valid surface
            val surface = surfaceHolder?.surface
            if (surface == null || !surface.isValid) {
                // Surface not ready yet — retry shortly (reset guard so retry can enter)
                synchronized(videoLock) { videoStarting = false }
                if (videoRetryCount < MAX_VIDEO_RETRIES) {
                    videoRetryCount++
                    Log.d(TAG, "Surface not ready, retry $videoRetryCount/$MAX_VIDEO_RETRIES")
                    handler.postDelayed({ startVideoWallpaper(path) }, 200)
                } else {
                    Log.e(TAG, "Surface never became ready after $MAX_VIDEO_RETRIES retries")
                    videoRetryCount = 0
                    isVideoWallpaper = false
                }
                return
            }
            videoRetryCount = 0

            val videoFile = File(path)
            if (!videoFile.exists()) {
                Log.e(TAG, "Video not found: $path")
                synchronized(videoLock) { videoStarting = false }
                isVideoWallpaper = false
                return
            }

            var mp: MediaPlayer? = null
            try {
                // Re-check surface validity right before use (can become invalid between check and use)
                val currentSurface = surfaceHolder?.surface
                if (currentSurface == null || !currentSurface.isValid) {
                    Log.w(TAG, "Surface became invalid before MediaPlayer setup")
                    synchronized(videoLock) { videoStarting = false }
                    isVideoWallpaper = false
                    return
                }
                val player = MediaPlayer()
                mp = player
                player.setDataSource(path)
                player.setSurface(currentSurface)
                player.setVolume(0f, 0f)
                player.isLooping = true

                player.setOnPreparedListener {
                    Log.d(TAG, "MediaPlayer READY: $path")
                    synchronized(videoLock) {
                        mediaPlayer = player
                        videoStarting = false
                    }
                    try { player.start() } catch (e: Exception) { Log.e(TAG, "start failed: ${e.message}") }
                }

                player.setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "MediaPlayer error: what=$what extra=$extra")
                    releaseMediaPlayerSafely(player)
                    synchronized(videoLock) {
                        if (mediaPlayer === player) mediaPlayer = null
                        videoStarting = false
                    }
                    isVideoWallpaper = false
                    handler.post {
                        drawing = true
                        handler.post(drawRunnable)
                    }
                    true
                }

                // Silence other events so GC never finds unhandled ones
                player.setOnCompletionListener { /* loop handles it */ }
                player.setOnInfoListener { _, _, _ -> true }
                player.setOnBufferingUpdateListener { _, _ -> }
                player.setOnSeekCompleteListener { /* no-op */ }
                player.setOnVideoSizeChangedListener { _, _, _ -> }

                player.prepareAsync()
                Log.d(TAG, "MediaPlayer preparing...")
            } catch (e: Exception) {
                Log.e(TAG, "MediaPlayer FAILED: ${e.javaClass.simpleName}: ${e.message}")
                e.printStackTrace()
                // Critical: release the local instance so it doesn't leak (was causing
                // "finalized without being released" and stuck Surface for next attempts)
                if (mp != null) releaseMediaPlayerSafely(mp)
                synchronized(videoLock) { videoStarting = false }
                isVideoWallpaper = false
            }
        }

        /**
         * Releases a MediaPlayer cleanly: clears all listeners (avoids "went away with
         * unhandled events"), detaches surface, stops, and releases native resources.
         */
        private fun releaseMediaPlayerSafely(mp: MediaPlayer) {
            try { mp.setOnPreparedListener(null) } catch (_: Exception) {}
            try { mp.setOnErrorListener(null) } catch (_: Exception) {}
            try { mp.setOnCompletionListener(null) } catch (_: Exception) {}
            try { mp.setOnInfoListener(null) } catch (_: Exception) {}
            try { mp.setOnBufferingUpdateListener(null) } catch (_: Exception) {}
            try { mp.setOnSeekCompleteListener(null) } catch (_: Exception) {}
            try { mp.setOnVideoSizeChangedListener(null) } catch (_: Exception) {}
            try { mp.setSurface(null) } catch (_: Exception) {}
            try { mp.stop() } catch (_: Exception) {}
            try { mp.reset() } catch (_: Exception) {}
            try { mp.release() } catch (_: Exception) {}
        }

        private fun stopVideoWallpaper() {
            handler.removeCallbacks(frameScrubUpdateRunnable)
            frameScrubRenderer.release()
            isFrameMode = false
            cachedDuration = 0L
            videoRetryCount = 0
            val mp: MediaPlayer?
            synchronized(videoLock) {
                mp = mediaPlayer
                mediaPlayer = null
                isVideoWallpaper = false
                videoStarting = false
            }
            if (mp != null) {
                releaseMediaPlayerSafely(mp)
                Log.d(TAG, "MediaPlayer released")
            }
        }

        private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
            val (height, width) = options.outHeight to options.outWidth
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

        private fun createScaledBitmap() {
            val bmp = wallpaperBitmap ?: return
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return

            // Invalidate old bitmaps under lock to prevent drawFrame reading recycled bitmap
            synchronized(bitmapLock) {
                scaledBitmap = null
                panoramicBitmap = null
            }

            // Capture dimensions at call time (they could change during thread execution)
            val targetW = surfaceWidth
            val targetH = surfaceHeight

            Thread {
                try {
                    val srcRatio = bmp.width.toFloat() / bmp.height.toFloat()
                    val dstRatio = targetW.toFloat() / targetH.toFloat()

                    val panoramic = srcRatio > dstRatio * 1.5f

                    if (panoramic) {
                        val scaledHeight = targetH
                        val scaledWidth = (bmp.width.toFloat() / bmp.height.toFloat() * scaledHeight).toInt()
                        val newPanBmp = Bitmap.createScaledBitmap(bmp, scaledWidth, scaledHeight, true)
                        synchronized(bitmapLock) {
                            // Only nullify wallpaperBitmap if it's still the same reference
                            // (prevents race condition when loadWallpaperImage sets a new bitmap
                            // between Thread start and finish)
                            if (wallpaperBitmap === bmp) wallpaperBitmap = null
                            scaledBitmap = null
                            panoramicBitmap = newPanBmp
                            isPanoramic = true
                        }
                        bmp.recycle()
                        Log.d(TAG, "Panoramic: ${scaledWidth}x${scaledHeight} (scroll range: ${scaledWidth - targetW}px)")
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
                        if (cropped != scaled) cropped.recycle()
                        synchronized(bitmapLock) {
                            if (wallpaperBitmap === bmp) wallpaperBitmap = null
                            panoramicBitmap = null
                            scaledBitmap = scaled
                            isPanoramic = false
                        }
                        bmp.recycle()
                    }
                    // Force a redraw with the new bitmap (verify surface still valid)
                    handler.post {
                        if (drawing && surfaceHolder?.surface?.isValid == true) drawFrame()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "createScaledBitmap error: ${e.message}")
                }
            }.start()
        }

        private fun updateRendererState() {
            // Sync shared state to all renderers
            clockRenderer.surfaceWidth = surfaceWidth
            clockRenderer.surfaceHeight = surfaceHeight
            clockRenderer.glowColor = glowColor
            clockRenderer.animationPhase = animationPhase

            equalizerRenderer.surfaceWidth = surfaceWidth
            equalizerRenderer.surfaceHeight = surfaceHeight
            equalizerRenderer.glowColor = glowColor
            equalizerRenderer.animationPhase = animationPhase

            rainRenderer.surfaceWidth = surfaceWidth
            rainRenderer.surfaceHeight = surfaceHeight
            rainRenderer.glowColor = glowColor
            rainRenderer.animationPhase = animationPhase
            rainRenderer.isRainWallpaper = isRainWallpaper
            rainRenderer.hasAudio = equalizerRenderer.hasAudio
            rainRenderer.smoothLevels = equalizerRenderer.smoothLevels

            batteryIndicator.surfaceWidth = surfaceWidth
            batteryIndicator.surfaceHeight = surfaceHeight
            batteryIndicator.glowColor = glowColor

            systemRings.surfaceWidth = surfaceWidth
            systemRings.surfaceHeight = surfaceHeight
            systemRings.glowColor = glowColor

            captionOverlay.surfaceWidth = surfaceWidth
            captionOverlay.surfaceHeight = surfaceHeight
            captionOverlay.glowColor = glowColor
        }

        override fun onOffsetsChanged(xOffset: Float, yOffset: Float, xStep: Float, yStep: Float, xPixelOffset: Int, yPixelOffset: Int) {
            if (isPanoramic && xStep > 0f && xStep < 1f) {
                val panBmp = panoramicBitmap
                if (panBmp != null) {
                    val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)
                    targetScrollPx = xOffset * maxScroll
                    scrollVelocity = 0f
                    if (!drawing) drawFrame()
                }
            }
        }

        override fun onSurfaceChanged(holder: SurfaceHolder?, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            val dimensionsChanged = surfaceWidth != width || surfaceHeight != height
            surfaceWidth = width
            surfaceHeight = height

            // Re-attach surface to existing MediaPlayer
            synchronized(videoLock) {
                val player = mediaPlayer
                if (player != null && holder?.surface != null && holder.surface.isValid) {
                    player.setSurface(holder.surface)
                    Log.d(TAG, "MediaPlayer surface re-attached")
                    return
                }
            }

            if (dimensionsChanged) {
                Log.d(TAG, "Surface changed: ${width}x${height}")
                loadWallpaperImage()
            }
            if (!isVideoWallpaper) {
                createScaledBitmap()
                drawFrame()
            }
        }

        override fun onVisibilityChanged(visible: Boolean) {
            Log.d(TAG, "visibility=$visible isVideo=$isVideoWallpaper isFrame=$isFrameMode videoStarting=$videoStarting")
            if (visible) {
                if (videoStarting) return

                // Frame mode (Explore): already rendering via Canvas, just resume drawing
                if (isFrameMode) {
                    if (!drawing) {
                        drawing = true
                        handler.post(drawRunnable)
                    }
                    return
                }

                // Video: resume MediaPlayer if still alive and playing
                val player = mediaPlayer
                if (player != null) {
                    try {
                        if (!isInteractive && !player.isPlaying) player.start()
                        Log.d(TAG, "MediaPlayer resumed")
                    } catch (e: Exception) {
                        Log.w(TAG, "MediaPlayer resume failed: ${e.message}")
                        // Player is in bad state, clean up
                        stopVideoWallpaper()
                    }
                    return
                }

                // Reload wallpaper config — may need to restart video
                loadWallpaperImage()
                if (!isVideoWallpaper && !videoStarting) {
                    createScaledBitmap()
                    equalizerRenderer.setupVisualizer()
                    drawing = true
                    handler.post(drawRunnable)
                }
            } else {
                // Only pause video, don't stop/release — it will be resumed on visibility=true
                val player = mediaPlayer
                if (player != null) {
                    player.pause()
                    Log.d(TAG, "MediaPlayer paused")
                } else if (!videoStarting) {
                    drawing = false
                    handler.removeCallbacks(drawRunnable)
                    equalizerRenderer.releaseVisualizer()
                }
            }
        }

        override fun onTouchEvent(event: MotionEvent?) {
            event ?: return

            // Interactive mode: tap position on screen = position in video/frames
            if (isInteractive && isVideoWallpaper) {
                if (event.action == MotionEvent.ACTION_DOWN) {
                    val pct = (event.x / surfaceWidth.toFloat()).coerceIn(0f, 1f)

                    if (isFrameMode && frameScrubRenderer.isReady) {
                        // Frame mode: seek through extracted frames
                        frameScrubRenderer.seekTo(pct)
                        // Restart animation loop to process the seek
                        handler.removeCallbacks(frameScrubUpdateRunnable)
                        handler.post(frameScrubUpdateRunnable)
                    } else {
                        // ExoPlayer fallback: animated seek
                        val player = mediaPlayer
                        if (player != null && player.duration > 0) {
                            player.seekTo((pct * player.duration).toInt().coerceIn(0, player.duration - 1))
                        }
                    }
                }
                return
            }

            // Panoramic touch scroll
            if (isPanoramic) {
                val panBmp = panoramicBitmap
                if (panBmp != null) {
                    val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            touchStartX = event.rawX
                            scrollVelocity = 0f
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val deltaX = touchStartX - event.rawX
                            touchStartX = event.rawX
                            scrollVelocity = deltaX * 2f
                            targetScrollPx = (targetScrollPx + deltaX * 2f).coerceIn(0f, maxScroll)
                        }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                            // Keep velocity for inertia fling
                        }
                    }
                }
            }

            when (event.action) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                    glowDots.add(GlowDot(event.x, event.y, System.currentTimeMillis(), glowColor))
                    if (!drawing) {
                        drawing = true
                        handler.post(drawRunnable)
                    }
                }
            }
        }

        private fun drawFrame() {
            if (!drawing) return
            val holder = surfaceHolder ?: return
            var canvas: Canvas? = null
            try {
                canvas = holder.lockCanvas() ?: return
                updateRendererState()

                // Frame mode: draw extracted frame instead of wallpaper bitmap
                if (isFrameMode && frameScrubRenderer.isReady) {
                    frameScrubRenderer.draw(canvas)
                } else {
                    drawBackground(canvas)
                }

                rainRenderer.draw(canvas)
                if (isRainWallpaper) rainRenderer.drawHeadphoneGlow(canvas)

                // Hide our clock on lock screen to avoid overlap with system clock
                val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                val isLocked = km?.isKeyguardLocked == true
                if (!isLocked) {
                    clockRenderer.draw(canvas)
                }
                batteryIndicator.draw(canvas)
                if (!isLocked) {
                    systemRings.draw(canvas)
                }
                equalizerRenderer.draw(canvas)
                if (!isLocked) captionOverlay.draw(canvas)
                drawGlowEffects(canvas)
            } catch (e: Exception) {
                Log.e(TAG, "drawFrame error: ${e.message}")
            } finally {
                if (canvas != null) {
                    try { holder.unlockCanvasAndPost(canvas) } catch (_: Exception) {}
                }
            }

            animationPhase += 0.05f

            val now = System.currentTimeMillis()
            glowDots.removeAll { now - it.startTime > GLOW_DURATION }

            // Switch to idle mode (low fps) when no audio and no touch
            val scrolling = isPanoramic && abs(scrollVelocity) > 0.5f
            if (!equalizerRenderer.hasAudio && glowDots.isEmpty() && !isRainWallpaper && !scrolling) {
                equalizerRenderer.silentFrames++
                if (equalizerRenderer.silentFrames > 30 && !idleMode) {
                    idleMode = true
                    equalizerRenderer.releaseVisualizer()
                }
            } else {
                equalizerRenderer.silentFrames = 0
                if (idleMode) {
                    idleMode = false
                    equalizerRenderer.setupVisualizer()
                }
            }
        }

        private fun drawBackground(canvas: Canvas) {
            // Read bitmap references under lock to prevent use-after-recycle
            val panBmp: Bitmap?
            val stdBmp: Bitmap?
            val pan: Boolean
            synchronized(bitmapLock) {
                panBmp = panoramicBitmap
                stdBmp = scaledBitmap
                pan = isPanoramic
            }

            if (pan && panBmp != null && !panBmp.isRecycled) {
                val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)

                if (abs(scrollVelocity) > 0.5f) {
                    targetScrollPx = (targetScrollPx + scrollVelocity).coerceIn(0f, maxScroll)
                    scrollVelocity *= 0.92f
                }
                scrollOffsetPx += (targetScrollPx - scrollOffsetPx) * 0.15f

                canvas.drawBitmap(panBmp, -scrollOffsetPx, 0f, null)
                return
            }
            if (stdBmp != null && !stdBmp.isRecycled) {
                canvas.drawBitmap(stdBmp, 0f, 0f, null)
            } else {
                canvas.drawColor(Color.BLACK)
            }
        }

        private fun drawGlowEffects(canvas: Canvas) {
            val now = System.currentTimeMillis()
            for (dot in glowDots) {
                val elapsed = now - dot.startTime
                val progress = (elapsed.toFloat() / GLOW_DURATION).coerceIn(0f, 1f)
                val radius = MAX_RADIUS * progress
                val alpha = ((1f - progress) * 0.45f * 255).toInt().coerceIn(0, 255)
                if (alpha <= 0 || radius <= 0f) continue

                val dr = Color.red(dot.color)
                val dg = Color.green(dot.color)
                val db = Color.blue(dot.color)

                glowDotPaint.shader = RadialGradient(
                    dot.x, dot.y, radius,
                    intArrayOf(
                        Color.argb(alpha, dr, dg, db),
                        Color.argb((alpha * 0.3f).toInt(), dr, dg, db),
                        Color.argb(0, dr, dg, db)
                    ),
                    floatArrayOf(0f, 0.5f, 1f),
                    Shader.TileMode.CLAMP
                )
                canvas.drawCircle(dot.x, dot.y, radius, glowDotPaint)
            }
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder?) {
            drawing = false
            handler.removeCallbacks(drawRunnable)
            pendingReload?.let { handler.removeCallbacks(it) }
            equalizerRenderer.releaseVisualizer()
            // Don't release ExoPlayer here — surface may be recreated (visibility change).
            // Only detach the surface so it doesn't draw to a destroyed one.
            synchronized(videoLock) {
                mediaPlayer?.setSurface(null)
            }
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            drawing = false
            handler.removeCallbacks(drawRunnable)
            pendingReload?.let { handler.removeCallbacks(it) }
            equalizerRenderer.releaseVisualizer()
            stopVideoWallpaper()
            batteryIndicator.release()
            unregisterPrefsListener()
            synchronized(bitmapLock) {
                wallpaperBitmap?.recycle()
                scaledBitmap?.recycle()
                panoramicBitmap?.recycle()
                wallpaperBitmap = null
                scaledBitmap = null
                panoramicBitmap = null
            }
            super.onDestroy()
        }
    }

    data class GlowDot(val x: Float, val y: Float, val startTime: Long, val color: Int)

    companion object {
        private const val TAG = "PixoraEQ"
        const val GLOW_DURATION = 700L
        const val MAX_RADIUS = 120f
        const val BAR_COUNT = 6
        const val FRAME_DELAY = 33L // ~30fps
        const val IDLE_FRAME_DELAY = 1000L
        const val SILENCE_THRESHOLD = 0.05f
        const val RAIN_DROP_COUNT = 120
        const val GLASS_DROP_COUNT = 15
        const val CITY_LIGHT_COUNT = 35
    }
}
