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
        private val fadePaint = Paint()
        private var videoFadeAlpha = 0f
        private val fadeRunnable = object : Runnable {
            override fun run() {
                val player = mediaPlayer ?: return
                if (!isVideoWallpaper) return

                val duration = player.duration.toLong()
                val position = player.currentPosition.toLong()
                val itemDuration = duration
                val itemPosition = position

                if (itemDuration <= 0) {
                    handler.postDelayed(this, 50)
                    return
                }

                val fadeMs = FADE_DURATION_MS
                val timeLeft = itemDuration - itemPosition

                videoFadeAlpha = when {
                    // Near end: fade to black
                    timeLeft < fadeMs -> ((fadeMs - timeLeft).toFloat() / fadeMs).coerceIn(0f, 1f)
                    // Near start: fade from black
                    itemPosition < fadeMs -> ((fadeMs - itemPosition).toFloat() / fadeMs).coerceIn(0f, 1f)
                    else -> 0f
                }

                // Draw overlay if fading
                if (videoFadeAlpha > 0.01f) {
                    val holder = surfaceHolder
                    var canvas: Canvas? = null
                    try {
                        canvas = holder?.lockCanvas()
                        if (canvas != null) {
                            // Don't clear — ExoPlayer already drew the video frame
                            // Just overlay black with alpha
                            fadePaint.color = Color.argb((videoFadeAlpha * 255).toInt(), 0, 0, 0)
                            canvas.drawRect(0f, 0f, canvas.width.toFloat(), canvas.height.toFloat(), fadePaint)
                        }
                    } catch (_: Exception) {
                    } finally {
                        if (canvas != null) {
                            try { holder?.unlockCanvasAndPost(canvas) } catch (_: Exception) {}
                        }
                    }
                }

                handler.postDelayed(this, 30) // ~33fps check
            }
        }

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
                        } else {
                            Log.e(TAG, "Failed to decode bitmap: $path")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadWallpaperImage error: ${e.message}")
            }
        }

        // Guard against multiple simultaneous video starts
        @Volatile private var videoStarting = false

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

            // Auto Play: use MediaPlayer
            val surface = surfaceHolder?.surface
            if (surface == null || !surface.isValid) {
                Log.e(TAG, "Surface not valid")
                synchronized(videoLock) { videoStarting = false }
                isVideoWallpaper = false
                return
            }

            val videoFile = File(path)
            if (!videoFile.exists()) {
                Log.e(TAG, "Video not found: $path")
                synchronized(videoLock) { videoStarting = false }
                isVideoWallpaper = false
                return
            }

            try {
                val mp = MediaPlayer()
                mp.setDataSource(path)
                mp.setSurface(surface)
                mp.setVolume(0f, 0f)
                mp.isLooping = true

                mp.setOnPreparedListener {
                    Log.d(TAG, "MediaPlayer READY: $path")
                    synchronized(videoLock) {
                        mediaPlayer = mp
                        videoStarting = false
                    }
                    try { mp.start() } catch (e: Exception) { Log.e(TAG, "start failed: ${e.message}") }
                    handler.removeCallbacks(fadeRunnable)
                    handler.postDelayed(fadeRunnable, 200)
                }

                mp.setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "MediaPlayer error: what=$what extra=$extra")
                    try { mp.release() } catch (_: Exception) {}
                    synchronized(videoLock) {
                        mediaPlayer = null
                        videoStarting = false
                    }
                    isVideoWallpaper = false
                    handler.post {
                        drawing = true
                        handler.post(drawRunnable)
                    }
                    true
                }

                mp.prepareAsync()
                Log.d(TAG, "MediaPlayer preparing...")
            } catch (e: Exception) {
                Log.e(TAG, "MediaPlayer FAILED: ${e.javaClass.simpleName}: ${e.message}")
                e.printStackTrace()
                synchronized(videoLock) { videoStarting = false }
                isVideoWallpaper = false
            }
        }

        private fun stopVideoWallpaper() {
            handler.removeCallbacks(fadeRunnable)
            handler.removeCallbacks(frameScrubUpdateRunnable)
            frameScrubRenderer.release()
            isFrameMode = false
            videoFadeAlpha = 0f
            val mp: MediaPlayer?
            synchronized(videoLock) {
                mp = mediaPlayer
                mediaPlayer = null
                isVideoWallpaper = false
                videoStarting = false
            }
            if (mp != null) {
                try {
                    mp.setSurface(null)
                    try { mp.stop() } catch (_: Exception) {}
                    mp.release()
                    Log.d(TAG, "MediaPlayer released")
                } catch (e: Exception) {
                    Log.w(TAG, "stopVideoWallpaper: ${e.message}")
                    try { mp.release() } catch (_: Exception) {}
                }
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
                            wallpaperBitmap = null
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
                            wallpaperBitmap = null
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

            // Re-attach surface to ExoPlayer if it was detached in onSurfaceDestroyed
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
        private const val FADE_DURATION_MS = 500L
    }
}
