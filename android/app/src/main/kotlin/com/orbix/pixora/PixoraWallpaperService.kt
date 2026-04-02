package com.orbix.pixora

import android.app.KeyguardManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.*
import android.net.Uri
import android.os.Handler
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
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
        private var scaledBitmap: Bitmap? = null
        private val glowDots = mutableListOf<GlowDot>()
        private var drawing = false
        private var surfaceWidth = 0
        private var surfaceHeight = 0
        private var glowColor = Color.parseColor("#7C4DFF")

        // Panoramic scroll
        private var isPanoramic = false
        private var panoramicBitmap: Bitmap? = null
        private var touchStartX = 0f
        private var scrollOffsetPx = 0f
        private var targetScrollPx = 0f
        private var scrollVelocity = 0f

        // Animation
        private var animationPhase = 0f
        private var idleMode = false
        private var isRainWallpaper = false
        private var currentWallpaperPath: String? = null

        // Video wallpaper (ExoPlayer)
        private var exoPlayer: ExoPlayer? = null
        private var isVideoWallpaper = false

        // Pre-allocated paint for glow dots
        private val glowDotPaint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Renderers
        private val clockRenderer = ClockRenderer()
        private val equalizerRenderer = EqualizerRenderer()
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
                    val delay = if (idleMode) IDLE_FRAME_DELAY else FRAME_DELAY
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

        private var pendingReload: Runnable? = null

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
                        val isVideo = path.endsWith(".mp4", ignoreCase = true) ||
                            path.endsWith(".webm", ignoreCase = true)

                        if (isVideo) {
                            startVideoWallpaper(path)
                            return
                        }

                        // Stop video if switching to image
                        stopVideoWallpaper()

                        val opts = BitmapFactory.Options()
                        opts.inJustDecodeBounds = true
                        BitmapFactory.decodeFile(path, opts)

                        val targetH = if (surfaceHeight > 0) surfaceHeight else 2340
                        opts.inSampleSize = calculateInSampleSize(opts, opts.outWidth, targetH)
                        opts.inJustDecodeBounds = false
                        opts.inPreferredConfig = Bitmap.Config.RGB_565
                        wallpaperBitmap = BitmapFactory.decodeFile(path, opts)
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // Guard against multiple simultaneous video starts
        private var videoStarting = false

        private fun startVideoWallpaper(path: String) {
            if (videoStarting) {
                Log.d(TAG, "Video already starting, skipping")
                return
            }
            videoStarting = true
            Log.d(TAG, "Starting ExoPlayer for: $path")

            // Stop canvas drawing
            drawing = false
            handler.removeCallbacks(drawRunnable)
            equalizerRenderer.releaseVisualizer()
            scaledBitmap = null
            panoramicBitmap = null
            wallpaperBitmap = null
            isVideoWallpaper = true

            // Release old player
            stopVideoWallpaper()
            isVideoWallpaper = true // stopVideoWallpaper resets this

            val surface = surfaceHolder?.surface
            if (surface == null || !surface.isValid) {
                Log.e(TAG, "Surface not valid for video")
                videoStarting = false
                isVideoWallpaper = false
                return
            }

            try {
                val player = ExoPlayer.Builder(applicationContext).build()
                player.setVideoSurface(surface)
                player.volume = 0f // Mute
                player.repeatMode = Player.REPEAT_MODE_ALL // Infinite loop

                val mediaItem = MediaItem.fromUri(Uri.fromFile(java.io.File(path)))
                player.setMediaItem(mediaItem)

                player.addListener(object : Player.Listener {
                    override fun onPlaybackStateChanged(state: Int) {
                        when (state) {
                            Player.STATE_READY -> {
                                Log.d(TAG, "ExoPlayer READY, starting: $path")
                                videoStarting = false
                                player.play()
                            }
                            Player.STATE_ENDED -> {
                                Log.d(TAG, "ExoPlayer ended (shouldn't happen with REPEAT_MODE_ALL)")
                            }
                        }
                    }
                    override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                        Log.e(TAG, "ExoPlayer error: ${error.message}")
                        videoStarting = false
                        isVideoWallpaper = false
                    }
                })

                player.prepare()
                exoPlayer = player
                Log.d(TAG, "ExoPlayer setup complete")
            } catch (e: Exception) {
                Log.e(TAG, "ExoPlayer FAILED: ${e.javaClass.simpleName}: ${e.message}")
                videoStarting = false
                isVideoWallpaper = false
            }
        }

        private fun stopVideoWallpaper() {
            val player = exoPlayer
            exoPlayer = null
            isVideoWallpaper = false
            videoStarting = false
            if (player != null) {
                try {
                    player.stop()
                    player.clearVideoSurface()
                    player.release()
                    Log.d(TAG, "ExoPlayer released")
                } catch (e: Exception) {
                    Log.w(TAG, "stopVideoWallpaper: ${e.message}")
                    try { player.release() } catch (_: Exception) {}
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

            // Invalidate old bitmaps immediately to prevent drawing stale frames
            scaledBitmap = null
            panoramicBitmap = null

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
                        panoramicBitmap = newPanBmp
                        scaledBitmap = null
                        isPanoramic = true
                        bmp.recycle()
                        wallpaperBitmap = null
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
                        scaledBitmap = scaled
                        panoramicBitmap = null
                        isPanoramic = false
                        bmp.recycle()
                        wallpaperBitmap = null
                    }
                    // Force a redraw with the new bitmap
                    handler.post { if (drawing) drawFrame() }
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
            Log.d(TAG, "visibility=$visible isVideo=$isVideoWallpaper exo=${exoPlayer != null}")
            if (visible) {
                if (videoStarting) return
                val player = exoPlayer
                if (player != null) {
                    // ExoPlayer exists — just resume
                    player.play()
                    Log.d(TAG, "ExoPlayer resumed")
                    return
                }
                // No video — load image wallpaper
                loadWallpaperImage()
                if (!isVideoWallpaper && !videoStarting) {
                    createScaledBitmap()
                    equalizerRenderer.setupVisualizer()
                    drawing = true
                    handler.post(drawRunnable)
                }
            } else {
                val player = exoPlayer
                if (player != null) {
                    player.pause()
                    Log.d(TAG, "ExoPlayer paused")
                } else if (!videoStarting) {
                    drawing = false
                    handler.removeCallbacks(drawRunnable)
                    equalizerRenderer.releaseVisualizer()
                }
            }
        }

        override fun onTouchEvent(event: MotionEvent?) {
            event ?: return

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
            val holder = surfaceHolder
            var canvas: Canvas? = null
            try {
                canvas = holder.lockCanvas()
                if (canvas != null) {
                    updateRendererState()
                    drawBackground(canvas)
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
                }
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
            val panBmp = panoramicBitmap
            if (isPanoramic && panBmp != null) {
                val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)

                if (abs(scrollVelocity) > 0.5f) {
                    targetScrollPx = (targetScrollPx + scrollVelocity).coerceIn(0f, maxScroll)
                    scrollVelocity *= 0.92f
                }
                scrollOffsetPx += (targetScrollPx - scrollOffsetPx) * 0.15f

                val scrollX = scrollOffsetPx
                canvas.drawBitmap(panBmp, -scrollX, 0f, null)
                return
            }
            val bmp = scaledBitmap
            if (bmp != null) {
                canvas.drawBitmap(bmp, 0f, 0f, null)
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
            equalizerRenderer.releaseVisualizer()
            stopVideoWallpaper()
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            drawing = false
            handler.removeCallbacks(drawRunnable)
            equalizerRenderer.releaseVisualizer()
            stopVideoWallpaper()
            batteryIndicator.release()
            unregisterPrefsListener()
            wallpaperBitmap?.recycle()
            scaledBitmap?.recycle()
            panoramicBitmap?.recycle()
            super.onDestroy()
        }
    }

    data class GlowDot(val x: Float, val y: Float, val startTime: Long, val color: Int)

    companion object {
        private const val TAG = "PixoraEQ"
        const val GLOW_DURATION = 700L
        const val MAX_RADIUS = 120f
        const val BAR_COUNT = 6
        const val FRAME_DELAY = 42L
        const val IDLE_FRAME_DELAY = 1000L
        const val SILENCE_THRESHOLD = 0.05f
        const val RAIN_DROP_COUNT = 120
        const val GLASS_DROP_COUNT = 15
        const val CITY_LIGHT_COUNT = 35
    }
}
