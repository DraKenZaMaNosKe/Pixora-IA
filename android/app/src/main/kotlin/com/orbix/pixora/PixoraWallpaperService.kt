package com.orbix.pixora

import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.*
import android.media.audiofx.Visualizer
import android.os.BatteryManager
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.content.SharedPreferences
import android.os.StatFs
import android.service.wallpaper.WallpaperService
import android.text.TextPaint
import android.util.Log
import android.view.MotionEvent
import android.view.SurfaceHolder
import java.io.File
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

class PixoraWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = PixoraEngine()

    inner class PixoraEngine : Engine() {
        private val handler = Handler(Looper.getMainLooper())
        private var wallpaperBitmap: Bitmap? = null
        private var scaledBitmap: Bitmap? = null
        private val glowDots = mutableListOf<GlowDot>()
        private var drawing = false
        private var surfaceWidth = 0
        private var surfaceHeight = 0
        private var glowColor = Color.parseColor("#7C4DFF")

        // Panoramic scroll
        private var xOffset = 0f
        private var isPanoramic = false
        private var panoramicBitmap: Bitmap? = null // full-width scaled bitmap
        private var touchStartX = 0f
        private var scrollOffsetPx = 0f // current scroll in pixels
        private var targetScrollPx = 0f // target for smooth interpolation
        private var scrollVelocity = 0f // for inertia/fling

        // Equalizer
        private var visualizer: Visualizer? = null
        private val currentLevels = FloatArray(BAR_COUNT)
        private val smoothLevels = FloatArray(BAR_COUNT)
        private val peakLevels = FloatArray(BAR_COUNT)
        private val peakDecay = FloatArray(BAR_COUNT)
        private var animationPhase = 0f
        private var hasAudio = false
        private var silentFrames = 0

        // Clock
        private val clockTimePaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        private val clockDatePaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        private val clockShadowPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        private val clockSecPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        private val clockArcPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val clockFlashPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var clockStyle = 0
        private var lastMinute = -1
        private var lastHour = -1
        private var hourFlashAlpha = 0f // for hour change flash effect

        // Pre-allocated paints (avoid GC pressure)
        private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val peakPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val overlayPaint = Paint()
        private val glowDotPaint = Paint(Paint.ANTI_ALIAS_FLAG)

        private var idleMode = false // true = low fps clock-only mode

        // Rain + scene effects (lofi_girl_rain only)
        private var isRainWallpaper = false
        private var currentWallpaperPath: String? = null
        private val rainDrops = mutableListOf<RainDrop>()
        private val glassDrops = mutableListOf<GlassDrop>()
        private val rainPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val glassPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var rainInitialized = false

        // City lights
        private val cityLights = mutableListOf<CityLight>()
        private val cityPaint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Lamp glow
        private val lampPaint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Headphone glow
        private val headphonePaint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Battery indicator
        private var batteryLevel = -1
        private var batteryCharging = false
        private var batteryPulsePhase = 0f
        private val batteryArcPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val batteryBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val batteryTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        private val batteryIconPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var batteryReceiver: BroadcastReceiver? = null

        // System rings (RAM + Storage)
        private var ramAvailableGB = 0f
        private var ramTotalGB = 0f
        private var storageAvailableGB = 0f
        private var storageTotalGB = 0f
        private var lastSystemRead = 0L
        private val systemRingPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val systemRingBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val systemTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        private val systemLabelPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        private var systemPulsePhase = 0f

        // Story caption overlay
        private var currentCaption: String? = null
        private val captionTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        private val captionBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var captionAlpha = 0f // for fade-in animation
        private var lastCaptionChange = 0L

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
            loadWallpaperImage()
            registerBatteryReceiver()
            registerPrefsListener()
            Log.d(TAG, "Engine onCreate")
        }

        private fun registerPrefsListener() {
            val prefs = applicationContext.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
            prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                if (key == "changed_at" || key == "wallpaper_path") {
                    Log.d(TAG, "Wallpaper changed by auto-rotate, reloading...")
                    handler.post {
                        loadWallpaperImage()
                        createScaledBitmap()
                    }
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

        private fun registerBatteryReceiver() {
            batteryReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    intent ?: return
                    val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                    val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                    val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                    batteryLevel = (level * 100) / scale
                    batteryCharging = status == BatteryManager.BATTERY_STATUS_CHARGING
                            || status == BatteryManager.BATTERY_STATUS_FULL
                }
            }
            val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            applicationContext.registerReceiver(batteryReceiver, filter)
        }

        private fun unregisterBatteryReceiver() {
            batteryReceiver?.let {
                try { applicationContext.unregisterReceiver(it) } catch (_: Exception) {}
            }
            batteryReceiver = null
        }

        private fun loadWallpaperImage() {
            try {
                val prefs = applicationContext.getSharedPreferences("pixora_live", 0)
                val path = prefs.getString("wallpaper_path", null)
                val color = prefs.getString("glow_color", "#7C4DFF")
                val caption = prefs.getString("caption", null)

                // Update caption with fade-in
                if (caption != currentCaption) {
                    currentCaption = caption
                    captionAlpha = 0f
                    lastCaptionChange = System.currentTimeMillis()
                }

                color?.let {
                    try { glowColor = Color.parseColor(it) } catch (_: Exception) {}
                }

                // Pick clock style based on wallpaper path hash
                clockStyle = abs((path ?: "").hashCode()) % 4
                currentWallpaperPath = path
                isRainWallpaper = path?.contains("lofi_girl_rain") == true

                if (path != null) {
                    val file = File(path)
                    if (file.exists()) {
                        // Decode with optimal sample size to save memory
                        val opts = BitmapFactory.Options()
                        opts.inJustDecodeBounds = true
                        BitmapFactory.decodeFile(path, opts)

                        // Target: screen height * 1.2 (enough quality, saves RAM)
                        val targetH = if (surfaceHeight > 0) surfaceHeight else 2340
                        opts.inSampleSize = calculateInSampleSize(opts, opts.outWidth, targetH)
                        opts.inJustDecodeBounds = false
                        opts.inPreferredConfig = Bitmap.Config.RGB_565 // half memory, no alpha needed
                        wallpaperBitmap = BitmapFactory.decodeFile(path, opts)
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
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

            Thread {
                val srcRatio = bmp.width.toFloat() / bmp.height.toFloat()
                val dstRatio = surfaceWidth.toFloat() / surfaceHeight.toFloat()

                // Detect panoramic: image is significantly wider than screen ratio
                isPanoramic = srcRatio > dstRatio * 1.5f

                if (isPanoramic) {
                    // Scale to fill screen height, keep full width for scrolling
                    val scaledHeight = surfaceHeight
                    val scaledWidth = (bmp.width.toFloat() / bmp.height.toFloat() * scaledHeight).toInt()
                    try {
                        panoramicBitmap = Bitmap.createScaledBitmap(bmp, scaledWidth, scaledHeight, true)
                        scaledBitmap = null
                        // Recycle original to free memory
                        bmp.recycle()
                        wallpaperBitmap = null
                        Log.d(TAG, "Panoramic: ${scaledWidth}x${scaledHeight} (scroll range: ${scaledWidth - surfaceWidth}px)")
                    } catch (e: Exception) {
                        Log.e(TAG, "createPanoramic error: ${e.message}")
                    }
                } else {
                    // Normal: center crop to fill screen
                    val (cropW, cropH) = if (srcRatio > dstRatio) {
                        Pair((bmp.height * dstRatio).toInt(), bmp.height)
                    } else {
                        Pair(bmp.width, (bmp.width / dstRatio).toInt())
                    }

                    val x = (bmp.width - cropW) / 2
                    val y = (bmp.height - cropH) / 2

                    try {
                        val cropped = Bitmap.createBitmap(bmp, x, y, cropW, cropH)
                        val scaled = Bitmap.createScaledBitmap(cropped, surfaceWidth, surfaceHeight, true)
                        if (cropped != scaled) cropped.recycle()
                        scaledBitmap = scaled
                        panoramicBitmap = null
                        isPanoramic = false
                        // Recycle original to free memory
                        bmp.recycle()
                        wallpaperBitmap = null
                    } catch (e: Exception) {
                        Log.e(TAG, "createScaledBitmap error: ${e.message}")
                    }
                }
            }.start()
        }

        private fun setupVisualizer() {
            releaseVisualizer()
            try {
                val viz = Visualizer(0)
                viz.captureSize = Visualizer.getCaptureSizeRange()[1]
                Log.d(TAG, "Visualizer captureSize=${viz.captureSize}")

                viz.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(v: Visualizer?, waveform: ByteArray?, samplingRate: Int) {}
                    override fun onFftDataCapture(v: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                        fft ?: return
                        processFFT(fft)
                    }
                }, Visualizer.getMaxCaptureRate(), false, true)

                viz.enabled = true
                visualizer = viz
                Log.d(TAG, "Visualizer enabled OK")
            } catch (e: Exception) {
                Log.e(TAG, "Visualizer failed: ${e.message}")
            }
        }

        private fun processFFT(fft: ByteArray) {
            val n = fft.size / 2
            for (i in 0 until BAR_COUNT) {
                val startBin = mapBarToFFTBin(i, n)
                val endBin = mapBarToFFTBin(i + 1, n)

                var magnitude = 0f
                var count = 0
                for (bin in startBin until min(endBin, n)) {
                    val idx = bin * 2
                    if (idx + 1 >= fft.size) break
                    val real = fft[idx].toFloat()
                    val imag = fft[idx + 1].toFloat()
                    magnitude += sqrt((real * real + imag * imag).toDouble()).toFloat()
                    count++
                }
                if (count > 0) magnitude /= count
                currentLevels[i] = (magnitude / 80f).coerceIn(0f, 1f)
            }

            // Detect if there's actual audio
            val maxLevel = currentLevels.max() ?: 0f
            val wasPlaying = hasAudio
            hasAudio = maxLevel > SILENCE_THRESHOLD

            // Clear levels immediately when music stops (avoid ghost bars)
            if (!hasAudio && wasPlaying) {
                currentLevels.fill(0f)
            }

            // Wake up draw loop when music starts
            if (hasAudio && !wasPlaying && !drawing) {
                silentFrames = 0
                drawing = true
                handler.post(drawRunnable)
            }
        }

        private fun mapBarToFFTBin(barIndex: Int, totalBins: Int): Int {
            val logMin = ln(1.0)
            val logMax = ln(totalBins.toDouble())
            val fraction = barIndex.toDouble() / BAR_COUNT
            return exp(logMin + fraction * (logMax - logMin)).toInt().coerceIn(1, totalBins)
        }

        private fun releaseVisualizer() {
            try {
                visualizer?.let { it.enabled = false; it.release() }
            } catch (_: Exception) {}
            visualizer = null
            // Clear audio levels to prevent ghost bars
            currentLevels.fill(0f)
            hasAudio = false
        }

        override fun onOffsetsChanged(xOffset: Float, yOffset: Float, xStep: Float, yStep: Float, xPixelOffset: Int, yPixelOffset: Int) {
            // Launcher scroll: update target in pixel space (same as touch scroll)
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
            surfaceWidth = width
            surfaceHeight = height
            createScaledBitmap()
            drawFrame()
        }

        override fun onVisibilityChanged(visible: Boolean) {
            Log.d(TAG, "visibility=$visible")
            if (visible) {
                loadWallpaperImage()
                createScaledBitmap()
                setupVisualizer()
                drawing = true
                handler.post(drawRunnable)
            } else {
                drawing = false
                handler.removeCallbacks(drawRunnable)
                releaseVisualizer()
            }
        }

        override fun onTouchEvent(event: MotionEvent?) {
            event ?: return

            // Panoramic touch scroll (always enabled — works on all launchers)
            if (isPanoramic) {
                val panBmp = panoramicBitmap
                if (panBmp != null) {
                    val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            touchStartX = event.rawX
                            scrollVelocity = 0f // stop inertia on touch
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val deltaX = touchStartX - event.rawX
                            touchStartX = event.rawX
                            scrollVelocity = deltaX * 2f // track velocity for fling
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
                    drawBackground(canvas)
                    if (isRainWallpaper) drawRainEffect(canvas)
                    // Hide our clock on lock screen to avoid overlap with system clock
                    val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    val isLocked = km?.isKeyguardLocked == true
                    if (!isLocked) {
                        drawClock(canvas)
                    }
                    drawBatteryIndicator(canvas)
                    if (!isLocked) {
                        drawSystemRings(canvas)
                    }
                    drawEqualizerBars(canvas)
                    if (!isLocked) drawCaption(canvas)
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
            // Rain wallpaper and active scroll stay at full fps
            val scrolling = isPanoramic && abs(scrollVelocity) > 0.5f
            if (!hasAudio && glowDots.isEmpty() && !isRainWallpaper && !scrolling) {
                silentFrames++
                if (silentFrames > 30 && !idleMode) {
                    idleMode = true
                    releaseVisualizer() // save CPU in idle
                }
            } else {
                silentFrames = 0
                if (idleMode) {
                    idleMode = false
                    setupVisualizer() // re-enable when active
                }
            }
        }

        private fun drawBackground(canvas: Canvas) {
            val panBmp = panoramicBitmap
            if (isPanoramic && panBmp != null) {
                val maxScroll = (panBmp.width - surfaceWidth).toFloat().coerceAtLeast(0f)

                // Apply inertia/fling
                if (abs(scrollVelocity) > 0.5f) {
                    targetScrollPx = (targetScrollPx + scrollVelocity).coerceIn(0f, maxScroll)
                    scrollVelocity *= 0.92f // friction
                }
                // Smooth interpolation toward target
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

        private fun drawClock(canvas: Canvas) {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return

            val cal = Calendar.getInstance()
            val hour = cal.get(Calendar.HOUR_OF_DAY)
            val minute = cal.get(Calendar.MINUTE)
            val second = cal.get(Calendar.SECOND)
            val millis = cal.get(Calendar.MILLISECOND)

            val timeStr = String.format(Locale.getDefault(), "%02d:%02d", hour, minute)
            val secStr = String.format(Locale.getDefault(), "%02d", second)
            val dayName = cal.getDisplayName(Calendar.DAY_OF_WEEK, Calendar.LONG, Locale.getDefault()) ?: ""
            val monthName = cal.getDisplayName(Calendar.MONTH, Calendar.LONG, Locale.getDefault()) ?: ""
            val dayNum = cal.get(Calendar.DAY_OF_MONTH)
            val dateStr = "${dayName.replaceFirstChar { it.uppercase() }}, $dayNum $monthName"

            val centerX = surfaceWidth / 2f
            val timeY = surfaceHeight * 0.15f
            val secY = timeY + surfaceHeight * 0.025f
            val dateY = secY + surfaceHeight * 0.035f
            val timeSize = surfaceWidth * 0.18f
            val dateSize = surfaceWidth * 0.035f
            val secSize = surfaceWidth * 0.06f

            // --- Minute countdown effects ---
            val secsLeft = 60 - second
            val isCountdown = secsLeft <= 10
            val countdownPulse = if (isCountdown) {
                // Pulse faster as we get closer: every 1s → every 0.3s
                val speed = 3f + (10 - secsLeft) * 0.7f
                (sin(animationPhase * speed.toDouble()).toFloat() * 0.5f + 0.5f)
            } else 1f

            // --- Hour change flash effect ---
            if (hour != lastHour && lastHour >= 0) {
                hourFlashAlpha = 1f
            }
            lastHour = hour
            if (hourFlashAlpha > 0f) {
                clockFlashPaint.color = glowColor
                clockFlashPaint.alpha = (hourFlashAlpha * 180).toInt()
                canvas.drawRect(0f, 0f, surfaceWidth.toFloat(), surfaceHeight.toFloat(), clockFlashPaint)
                hourFlashAlpha = max(0f, hourFlashAlpha - 0.02f)
            }

            // --- Seconds arc (circular progress around time) ---
            val arcRadius = timeSize * 0.85f
            val arcRect = RectF(
                centerX - arcRadius, timeY - timeSize * 0.6f - arcRadius * 0.3f,
                centerX + arcRadius, timeY - timeSize * 0.6f + arcRadius * 1.3f
            )
            val sweepAngle = ((second * 1000 + millis) / 60000f) * 360f
            clockArcPaint.apply {
                style = Paint.Style.STROKE
                strokeWidth = 3f
                strokeCap = Paint.Cap.ROUND
                color = glowColor
                alpha = if (isCountdown) (countdownPulse * 200 + 55).toInt() else 60
                shader = null
            }
            canvas.drawArc(arcRect, -90f, sweepAngle, false, clockArcPaint)

            // Glow dot at arc tip
            val tipAngle = Math.toRadians((-90 + sweepAngle).toDouble())
            val tipX = centerX + arcRadius * cos(tipAngle).toFloat()
            val tipY = (arcRect.centerY()) + arcRadius * 0.8f * sin(tipAngle).toFloat()
            clockArcPaint.apply {
                style = Paint.Style.FILL
                alpha = if (isCountdown) (countdownPulse * 255).toInt() else 150
            }
            canvas.drawCircle(tipX, tipY, 5f, clockArcPaint)

            // --- Time text with countdown blink ---
            val timeAlpha = if (isCountdown) (countdownPulse * 105 + 150).toInt() else 255

            when (clockStyle) {
                0 -> { // Neon Glow
                    clockShadowPaint.apply {
                        color = glowColor
                        textSize = timeSize
                        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                        textAlign = Paint.Align.CENTER
                        letterSpacing = 0.08f
                        alpha = 80
                        setShadowLayer(50f, 0f, 0f, glowColor)
                    }
                    canvas.drawText(timeStr, centerX, timeY, clockShadowPaint)
                    clockTimePaint.apply {
                        color = Color.WHITE
                        textSize = timeSize
                        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                        textAlign = Paint.Align.CENTER
                        letterSpacing = 0.08f
                        alpha = timeAlpha
                        shader = null
                        setShadowLayer(30f, 0f, 0f, glowColor)
                    }
                    canvas.drawText(timeStr, centerX, timeY, clockTimePaint)
                }
                1 -> { // Clean Minimal
                    clockTimePaint.apply {
                        color = Color.WHITE
                        textSize = timeSize * 0.9f
                        typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
                        textAlign = Paint.Align.CENTER
                        letterSpacing = 0.12f
                        alpha = timeAlpha
                        shader = null
                        setShadowLayer(8f, 0f, 2f, Color.argb(100, 0, 0, 0))
                    }
                    canvas.drawText(timeStr, centerX, timeY, clockTimePaint)
                }
                2 -> { // Bold Shadow
                    clockShadowPaint.apply {
                        color = glowColor
                        textSize = timeSize * 1.05f
                        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                        textAlign = Paint.Align.CENTER
                        letterSpacing = 0.02f
                        alpha = 150
                        setShadowLayer(0f, 0f, 0f, 0)
                    }
                    canvas.drawText(timeStr, centerX + 4f, timeY + 4f, clockShadowPaint)
                    clockTimePaint.apply {
                        color = Color.WHITE
                        textSize = timeSize * 1.05f
                        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                        textAlign = Paint.Align.CENTER
                        letterSpacing = 0.02f
                        alpha = timeAlpha
                        shader = null
                        setShadowLayer(0f, 0f, 0f, 0)
                    }
                    canvas.drawText(timeStr, centerX, timeY, clockTimePaint)
                }
                3 -> { // Gradient Fade
                    clockTimePaint.apply {
                        textSize = timeSize
                        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                        textAlign = Paint.Align.CENTER
                        letterSpacing = 0.06f
                        alpha = timeAlpha
                        shader = LinearGradient(
                            centerX - timeSize, timeY - timeSize * 0.8f,
                            centerX + timeSize, timeY,
                            intArrayOf(Color.WHITE, glowColor), null, Shader.TileMode.CLAMP
                        )
                        setShadowLayer(15f, 0f, 0f, Color.argb(100, 0, 0, 0))
                    }
                    canvas.drawText(timeStr, centerX, timeY, clockTimePaint)
                    clockTimePaint.shader = null
                }
            }

            // --- Seconds with color cycle effect ---
            val secHue = (second / 60f) * 360f
            val secColor = Color.HSVToColor(200, floatArrayOf(secHue, 0.6f, 1f))
            val secGlowColor = Color.HSVToColor(100, floatArrayOf(secHue, 0.8f, 1f))

            // Seconds text - right of time with breathing glow
            val timeWidth = clockTimePaint.measureText(timeStr)
            val secX = centerX + timeWidth / 2 + surfaceWidth * 0.04f

            clockSecPaint.apply {
                color = secColor
                textSize = secSize
                typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
                textAlign = Paint.Align.LEFT
                letterSpacing = 0.05f
                val breathe = sin(animationPhase * 2.0).toFloat() * 8f + 12f
                setShadowLayer(breathe, 0f, 0f, secGlowColor)
            }
            canvas.drawText(secStr, secX, timeY, clockSecPaint)

            // --- Milliseconds as tiny dots (3 dots that fade in sequence) ---
            val msProgress = millis / 1000f
            val dotSpacing = surfaceWidth * 0.012f
            val dotY = timeY + surfaceHeight * 0.012f
            val dotBaseX = secX + clockSecPaint.measureText(secStr) + dotSpacing

            for (d in 0 until 3) {
                val dotProgress = ((msProgress * 3f) - d).coerceIn(0f, 1f)
                val dotAlpha = (dotProgress * 200).toInt()
                val dotRadius = 2.5f + dotProgress * 1.5f
                clockArcPaint.apply {
                    style = Paint.Style.FILL
                    color = secColor
                    alpha = dotAlpha
                    shader = null
                }
                canvas.drawCircle(dotBaseX + d * dotSpacing, dotY, dotRadius, clockArcPaint)
            }

            // --- Date ---
            clockDatePaint.apply {
                textSize = dateSize
                textAlign = Paint.Align.CENTER
                letterSpacing = 0.15f
                shader = null
                setShadowLayer(6f, 0f, 0f, Color.argb(80, 0, 0, 0))
                color = when (clockStyle) {
                    0 -> { // Neon: glow colored date
                        setShadowLayer(10f, 0f, 0f, glowColor)
                        glowColor
                    }
                    2 -> Color.WHITE // Bold: white date
                    else -> Color.argb(180, 255, 255, 255) // Others: subtle white
                }
                alpha = if (clockStyle == 0) 200 else if (clockStyle == 2) 200 else 180
            }
            val displayDate = if (clockStyle == 0 || clockStyle == 2) dateStr.uppercase() else dateStr
            canvas.drawText(displayDate, centerX, dateY, clockDatePaint)

            lastMinute = minute
        }

        // ── Rain effect (lofi_girl_rain only) ──────────────────────────
        // Window region in normalized coords (0..1) based on the lofi_girl_rain image
        private val winLeft   = 0.0f
        private val winRight  = 0.47f
        private val winTop    = 0.0f
        private val winBottom = 0.53f

        private fun initRain() {
            if (rainInitialized || surfaceWidth <= 0 || surfaceHeight <= 0) return
            rainInitialized = true

            val wL = winLeft * surfaceWidth
            val wR = winRight * surfaceWidth
            val wT = winTop * surfaceHeight
            val wB = winBottom * surfaceHeight
            val regionW = wR - wL
            val regionH = wB - wT

            // Falling rain streaks — only inside window
            for (i in 0 until RAIN_DROP_COUNT) {
                rainDrops.add(RainDrop(
                    x = wL + Random.nextFloat() * regionW,
                    y = wT + Random.nextFloat() * regionH,
                    speed = 8f + Random.nextFloat() * 14f,
                    length = 15f + Random.nextFloat() * 30f,
                    alpha = 30 + Random.nextInt(55),
                    windOffset = Random.nextFloat() * 1.5f - 0.3f
                ))
            }

            // Glass drops on window surface
            for (i in 0 until GLASS_DROP_COUNT) {
                glassDrops.add(GlassDrop(
                    x = wL + Random.nextFloat() * regionW,
                    y = wT + Random.nextFloat() * regionH,
                    radius = 2f + Random.nextFloat() * 3.5f,
                    slideSpeed = 0.3f + Random.nextFloat() * 1.0f,
                    trailLength = 25f + Random.nextFloat() * 60f,
                    alpha = 20 + Random.nextInt(40)
                ))
            }

            // City lights — scattered across the city skyline area in the window
            // City is roughly x=2-44%, y=5-38% of image
            val cityColors = intArrayOf(
                Color.rgb(255, 220, 120),  // warm yellow
                Color.rgb(255, 180, 100),  // orange
                Color.rgb(255, 150, 200),  // pink/magenta
                Color.rgb(180, 160, 255),  // purple
                Color.rgb(120, 200, 255),  // cool blue
                Color.rgb(255, 255, 200),  // white-warm
            )
            // City lights inside window but away from right edge (girl's hair covers it)
            val cityRight = 0.36f // narrower than window to avoid hair overlap
            for (i in 0 until CITY_LIGHT_COUNT) {
                val cx = (winLeft + 0.02f + Random.nextFloat() * (cityRight - winLeft - 0.04f)) * surfaceWidth
                val cy = (winTop + 0.05f + Random.nextFloat() * (winBottom - winTop - 0.10f)) * surfaceHeight
                cityLights.add(CityLight(
                    x = cx, y = cy,
                    baseAlpha = 80 + Random.nextInt(100),
                    flickerSpeed = 0.5f + Random.nextFloat() * 3f,
                    flickerOffset = Random.nextFloat() * 6.28f,
                    radius = 3f + Random.nextFloat() * 5f,
                    color = cityColors[Random.nextInt(cityColors.size)]
                ))
            }
        }

        private fun drawRainEffect(canvas: Canvas) {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return
            if (!rainInitialized) initRain()

            val w = surfaceWidth.toFloat()
            val h = surfaceHeight.toFloat()

            // Window bounds in pixels
            val wL = winLeft * w
            val wR = winRight * w
            val wT = winTop * h
            val wB = winBottom * h
            val regionW = wR - wL

            // Clip all rain drawing to the window region
            canvas.save()
            canvas.clipRect(wL, wT, wR, wB)

            // 1) Slight blue-dark overlay on window only (rainy atmosphere)
            overlayPaint.color = Color.argb(12, 0, 10, 30)
            canvas.drawRect(wL, wT, wR, wB, overlayPaint)

            // 2) Falling rain streaks (diagonal, fast) — window only
            rainPaint.strokeCap = Paint.Cap.ROUND
            for (drop in rainDrops) {
                drop.y += drop.speed
                drop.x += drop.windOffset + 1.2f

                // Reset to top of window when passing bottom
                if (drop.y > wB + drop.length) {
                    drop.y = wT - drop.length
                    drop.x = wL + Random.nextFloat() * regionW
                }
                // Wrap horizontally within window
                if (drop.x > wR + 10f) {
                    drop.x = wL - 5f
                }

                rainPaint.color = Color.argb(drop.alpha, 180, 200, 220)
                rainPaint.strokeWidth = 1.2f

                val endX = drop.x + drop.length * 0.1f
                val endY = drop.y + drop.length
                canvas.drawLine(drop.x, drop.y, endX, endY, rainPaint)
            }

            // 3) Glass drops (slow round drops sliding down window)
            for (drop in glassDrops) {
                drop.y += drop.slideSpeed
                drop.x += sin((animationPhase * 0.5f + drop.x * 0.01f).toDouble()).toFloat() * 0.25f

                if (drop.y > wB + drop.trailLength) {
                    drop.y = wT - drop.trailLength
                    drop.x = wL + Random.nextFloat() * regionW
                }

                // Trail line
                glassPaint.color = Color.argb(drop.alpha / 2, 160, 190, 210)
                glassPaint.strokeWidth = drop.radius * 0.5f
                glassPaint.strokeCap = Paint.Cap.ROUND
                glassPaint.style = Paint.Style.STROKE
                canvas.drawLine(
                    drop.x, drop.y - drop.trailLength,
                    drop.x, drop.y,
                    glassPaint
                )

                // Drop circle
                glassPaint.style = Paint.Style.FILL
                glassPaint.color = Color.argb(drop.alpha, 200, 215, 230)
                canvas.drawCircle(drop.x, drop.y, drop.radius, glassPaint)

                // Bright highlight
                glassPaint.color = Color.argb(drop.alpha + 15, 240, 245, 255)
                canvas.drawCircle(
                    drop.x - drop.radius * 0.3f,
                    drop.y - drop.radius * 0.3f,
                    drop.radius * 0.3f,
                    glassPaint
                )
            }

            // 4) City lights flickering in the buildings — RadialGradient bloom
            for (light in cityLights) {
                val flicker = sin((animationPhase * light.flickerSpeed + light.flickerOffset).toDouble()).toFloat()
                val alpha = (light.baseAlpha + flicker * 60).toInt().coerceIn(20, 255)
                val bloomRadius = light.radius * 5f

                val lr = Color.red(light.color)
                val lg = Color.green(light.color)
                val lb = Color.blue(light.color)

                // Bloom glow (RadialGradient — works on HW canvas)
                cityPaint.shader = RadialGradient(
                    light.x, light.y, bloomRadius,
                    intArrayOf(
                        Color.argb(alpha, lr, lg, lb),
                        Color.argb((alpha * 0.4f).toInt(), lr, lg, lb),
                        Color.argb(0, lr, lg, lb)
                    ),
                    floatArrayOf(0f, 0.3f, 1f),
                    Shader.TileMode.CLAMP
                )
                canvas.drawCircle(light.x, light.y, bloomRadius, cityPaint)
                cityPaint.shader = null

                // Bright center dot
                cityPaint.color = Color.argb(min(255, alpha + 60), lr, lg, lb)
                canvas.drawCircle(light.x, light.y, light.radius, cityPaint)
            }

            // 5) Occasional lightning flash (only on window area)
            val flashChance = (animationPhase * 30f).toInt() % 600
            if (flashChance == 0) {
                overlayPaint.color = Color.argb(18, 200, 210, 255)
                canvas.drawRect(wL, wT, wR, wB, overlayPaint)
            }

            canvas.restore()

            // Effects outside window (no clip)
            drawLampGlow(canvas)
        }

        private fun drawLampGlow(canvas: Canvas) {
            if (surfaceWidth <= 0 || surfaceHeight <= 0 || !isRainWallpaper) return
            val w = surfaceWidth.toFloat()
            val h = surfaceHeight.toFloat()

            // Lamp bulb center — calibrated from touch
            val lampX = 0.06f * w
            val lampY = 0.41f * h
            // Book/desk center — light projects downward-right toward the book
            val bookX = 0.30f * w
            val bookY = 0.68f * h

            val pulse = sin((animationPhase * 0.5).toDouble()).toFloat() * 0.08f + 0.92f

            // 1) Bright bulb point
            val bulbRadius = w * 0.045f
            lampPaint.shader = RadialGradient(
                lampX, lampY, bulbRadius,
                intArrayOf(
                    Color.argb(255, 255, 250, 230),   // white-hot center
                    Color.argb(220, 255, 230, 160),
                    Color.argb(0, 255, 200, 100)
                ),
                floatArrayOf(0f, 0.5f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(lampX, lampY, bulbRadius, lampPaint)

            // 2) Light cone toward the book
            val coneRadius = w * 0.40f * pulse

            lampPaint.shader = RadialGradient(
                lampX, lampY, coneRadius,
                intArrayOf(
                    Color.argb((230 * pulse).toInt(), 255, 220, 140),
                    Color.argb((150 * pulse).toInt(), 255, 200, 100),
                    Color.argb((60 * pulse).toInt(), 255, 175, 70),
                    Color.argb(0, 255, 150, 40)
                ),
                floatArrayOf(0f, 0.15f, 0.45f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.save()
            canvas.translate(lampX, lampY)
            canvas.scale(1f, 1.8f)
            canvas.translate(-lampX, -lampY)
            canvas.drawCircle(lampX, lampY, coneRadius, lampPaint)
            canvas.restore()

            // 3) Warm glow on the book/desk area
            val bookGlow = w * 0.22f
            lampPaint.shader = RadialGradient(
                bookX, bookY, bookGlow,
                intArrayOf(
                    Color.argb((120 * pulse).toInt(), 255, 215, 140),
                    Color.argb((55 * pulse).toInt(), 255, 195, 100),
                    Color.argb(0, 255, 170, 60)
                ),
                floatArrayOf(0f, 0.45f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(bookX, bookY, bookGlow, lampPaint)
            lampPaint.shader = null
        }

        private fun drawHeadphoneGlow(canvas: Canvas) {
            if (surfaceWidth <= 0 || surfaceHeight <= 0 || !isRainWallpaper) return

            val w = surfaceWidth.toFloat()
            val h = surfaceHeight.toFloat()

            // Headphones center — calibrated from screenshot
            val hpX = 0.62f * w
            val hpY = 0.30f * h

            val gr = Color.red(glowColor)
            val gg = Color.green(glowColor)
            val gb = Color.blue(glowColor)

            // Always show a subtle breathing glow on headphones
            val breathe = sin((animationPhase * 0.7).toDouble()).toFloat() * 0.3f + 0.7f
            val idleRadius = w * 0.09f * breathe
            val idleAlpha = (60 * breathe).toInt()

            headphonePaint.shader = RadialGradient(
                hpX, hpY, idleRadius,
                intArrayOf(
                    Color.argb(idleAlpha, gr, gg, gb),
                    Color.argb((idleAlpha * 0.3f).toInt(), gr, gg, gb),
                    Color.argb(0, gr, gg, gb)
                ),
                floatArrayOf(0f, 0.4f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(hpX, hpY, idleRadius, headphonePaint)
            headphonePaint.shader = null

            // When music plays, add reactive pulse on top
            if (hasAudio) {
                val avgLevel = smoothLevels.average().toFloat()
                val intensity = (avgLevel * 3f).coerceIn(0f, 1f)
                if (intensity > 0.02f) {
                    val beatRadius = w * 0.12f + intensity * w * 0.10f
                    val beatAlpha = (intensity * 120).toInt().coerceIn(0, 140)

                    headphonePaint.shader = RadialGradient(
                        hpX, hpY, beatRadius,
                        intArrayOf(
                            Color.argb(beatAlpha, gr, gg, gb),
                            Color.argb((beatAlpha * 0.3f).toInt(), gr, gg, gb),
                            Color.argb(0, gr, gg, gb)
                        ),
                        floatArrayOf(0f, 0.4f, 1f),
                        Shader.TileMode.CLAMP
                    )
                    canvas.drawCircle(hpX, hpY, beatRadius, headphonePaint)
                    headphonePaint.shader = null

                    // Pulse ring
                    val ringAlpha = (intensity * 50).toInt()
                    headphonePaint.style = Paint.Style.STROKE
                    headphonePaint.strokeWidth = 2.5f
                    headphonePaint.color = Color.argb(ringAlpha, gr, gg, gb)
                    val ringRadius = beatRadius * (0.7f + sin((animationPhase * 4f).toDouble()).toFloat() * 0.3f)
                    canvas.drawCircle(hpX, hpY, ringRadius, headphonePaint)
                    headphonePaint.style = Paint.Style.FILL
                }
            }
        }

        private fun drawBatteryIndicator(canvas: Canvas) {
            if (batteryLevel < 0 || surfaceWidth <= 0 || surfaceHeight <= 0) return

            val w = surfaceWidth.toFloat()
            val h = surfaceHeight.toFloat()

            // Position: top-left area
            val radius = w * 0.055f // ring radius
            val centerX = radius + w * 0.05f
            val centerY = h * 0.12f
            val strokeWidth = radius * 0.22f

            // Colors based on battery level and wallpaper glow
            val r = Color.red(glowColor)
            val g = Color.green(glowColor)
            val b = Color.blue(glowColor)

            val arcColor = when {
                batteryLevel <= 15 -> Color.rgb(255, 50, 50) // red critical
                batteryLevel <= 30 -> Color.rgb(255, 165, 0) // orange low
                else -> glowColor // wallpaper glow color
            }

            // Charging pulse animation
            if (batteryCharging) {
                batteryPulsePhase += 0.06f
                if (batteryPulsePhase > Math.PI.toFloat() * 2f) batteryPulsePhase = 0f
            }
            val pulseAlpha = if (batteryCharging) {
                (0.4f + 0.6f * ((sin(batteryPulsePhase) + 1f) / 2f))
            } else 1f

            // Background ring (dark)
            batteryBgPaint.style = Paint.Style.STROKE
            batteryBgPaint.strokeWidth = strokeWidth
            batteryBgPaint.strokeCap = Paint.Cap.ROUND
            batteryBgPaint.color = Color.argb(60, 255, 255, 255)
            val arcRect = RectF(
                centerX - radius, centerY - radius,
                centerX + radius, centerY + radius
            )
            canvas.drawArc(arcRect, -90f, 360f, false, batteryBgPaint)

            // Battery arc (colored, proportional to level)
            val sweepAngle = batteryLevel * 3.6f // 100% = 360°
            batteryArcPaint.style = Paint.Style.STROKE
            batteryArcPaint.strokeWidth = strokeWidth
            batteryArcPaint.strokeCap = Paint.Cap.ROUND
            batteryArcPaint.color = arcColor
            batteryArcPaint.alpha = (255 * pulseAlpha).toInt()

            // Glow effect behind arc
            batteryArcPaint.setShadowLayer(radius * 0.5f, 0f, 0f, arcColor)
            canvas.drawArc(arcRect, -90f, sweepAngle, false, batteryArcPaint)
            batteryArcPaint.clearShadowLayer()

            // Percentage text
            val text = "$batteryLevel"
            batteryTextPaint.textSize = radius * 0.75f
            batteryTextPaint.textAlign = Paint.Align.CENTER
            batteryTextPaint.typeface = Typeface.create("sans-serif-light", Typeface.BOLD)
            batteryTextPaint.color = Color.WHITE
            batteryTextPaint.alpha = (230 * pulseAlpha).toInt()
            val textY = centerY + batteryTextPaint.textSize * 0.35f
            canvas.drawText(text, centerX, textY, batteryTextPaint)

            // Small "%" below
            batteryTextPaint.textSize = radius * 0.32f
            batteryTextPaint.alpha = (150 * pulseAlpha).toInt()
            canvas.drawText("%", centerX, textY + radius * 0.4f, batteryTextPaint)

            // Charging bolt icon
            if (batteryCharging) {
                batteryIconPaint.color = arcColor
                batteryIconPaint.alpha = (200 * pulseAlpha).toInt()
                batteryIconPaint.style = Paint.Style.FILL
                val boltSize = radius * 0.3f
                val bx = centerX + radius + strokeWidth * 0.8f
                val by = centerY - radius * 0.3f
                val bolt = Path()
                bolt.moveTo(bx - boltSize * 0.2f, by - boltSize)
                bolt.lineTo(bx - boltSize * 0.5f, by + boltSize * 0.1f)
                bolt.lineTo(bx - boltSize * 0.05f, by + boltSize * 0.1f)
                bolt.lineTo(bx + boltSize * 0.2f, by + boltSize)
                bolt.lineTo(bx + boltSize * 0.5f, by - boltSize * 0.1f)
                bolt.lineTo(bx + boltSize * 0.05f, by - boltSize * 0.1f)
                bolt.close()
                canvas.drawPath(bolt, batteryIconPaint)
            }
        }

        private fun readSystemInfo() {
            val now = System.currentTimeMillis()
            if (now - lastSystemRead < 5000) return // read every 5 seconds max
            lastSystemRead = now

            try {
                // RAM
                val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                if (am != null) {
                    val memInfo = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(memInfo)
                    ramAvailableGB = memInfo.availMem / (1024f * 1024f * 1024f)
                    ramTotalGB = memInfo.totalMem / (1024f * 1024f * 1024f)
                }

                // Storage
                val stat = StatFs(Environment.getDataDirectory().path)
                storageTotalGB = (stat.blockSizeLong * stat.blockCountLong) / (1024f * 1024f * 1024f)
                storageAvailableGB = (stat.blockSizeLong * stat.availableBlocksLong) / (1024f * 1024f * 1024f)
            } catch (_: Exception) {}
        }

        private fun drawSystemRings(canvas: Canvas) {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return
            readSystemInfo()
            if (ramTotalGB <= 0f && storageTotalGB <= 0f) return

            val w = surfaceWidth.toFloat()
            val h = surfaceHeight.toFloat()

            // Animate a subtle breathing pulse
            systemPulsePhase += 0.02f
            if (systemPulsePhase > Math.PI.toFloat() * 2f) systemPulsePhase = 0f
            val breathe = 0.85f + 0.15f * sin(systemPulsePhase)

            // Position: below battery ring, left side
            val batteryRadius = w * 0.055f
            val batteryY = h * 0.12f
            val startY = batteryY + batteryRadius * 2.8f // below battery

            val ringRadius = w * 0.04f // smaller than battery
            val spacing = ringRadius * 3.2f
            val leftX = ringRadius + w * 0.055f

            // --- RAM Ring ---
            val ramPct = if (ramTotalGB > 0) ((ramTotalGB - ramAvailableGB) / ramTotalGB * 100f) else 0f
            val ramColor = when {
                ramPct > 90 -> Color.rgb(255, 50, 50) // critical
                ramPct > 75 -> Color.rgb(255, 165, 0) // high
                else -> glowColor
            }
            drawMiniRing(
                canvas, leftX, startY, ringRadius,
                ramPct, ramColor, breathe,
                String.format("%.1f", ramAvailableGB), "GB", "RAM"
            )

            // --- Storage Ring ---
            val storagePct = if (storageTotalGB > 0) ((storageTotalGB - storageAvailableGB) / storageTotalGB * 100f) else 0f
            val storageColor = when {
                storagePct > 90 -> Color.rgb(255, 50, 50)
                storagePct > 75 -> Color.rgb(255, 165, 0)
                else -> glowColor
            }
            drawMiniRing(
                canvas, leftX, startY + spacing, ringRadius,
                storagePct, storageColor, breathe,
                if (storageAvailableGB >= 10) String.format("%.0f", storageAvailableGB)
                else String.format("%.1f", storageAvailableGB),
                "GB", "DISK"
            )
        }

        private fun drawMiniRing(
            canvas: Canvas, cx: Float, cy: Float, radius: Float,
            usedPct: Float, color: Int, breathe: Float,
            value: String, unit: String, label: String
        ) {
            val strokeWidth = radius * 0.25f

            // Background ring
            systemRingBgPaint.style = Paint.Style.STROKE
            systemRingBgPaint.strokeWidth = strokeWidth
            systemRingBgPaint.strokeCap = Paint.Cap.ROUND
            systemRingBgPaint.color = Color.argb(40, 255, 255, 255)
            val rect = RectF(cx - radius, cy - radius, cx + radius, cy + radius)
            canvas.drawArc(rect, -90f, 360f, false, systemRingBgPaint)

            // Colored arc
            val sweep = usedPct * 3.6f
            systemRingPaint.style = Paint.Style.STROKE
            systemRingPaint.strokeWidth = strokeWidth
            systemRingPaint.strokeCap = Paint.Cap.ROUND
            systemRingPaint.color = color
            systemRingPaint.alpha = (255 * breathe).toInt()
            systemRingPaint.setShadowLayer(radius * 0.4f, 0f, 0f, color)
            canvas.drawArc(rect, -90f, sweep, false, systemRingPaint)
            systemRingPaint.clearShadowLayer()

            // Value text (right of ring)
            val textX = cx + radius + strokeWidth + radius * 0.4f
            systemTextPaint.textSize = radius * 0.85f
            systemTextPaint.textAlign = Paint.Align.LEFT
            systemTextPaint.typeface = Typeface.create("sans-serif-condensed", Typeface.BOLD)
            systemTextPaint.color = Color.WHITE
            systemTextPaint.alpha = (220 * breathe).toInt()
            canvas.drawText(value, textX, cy + radius * 0.15f, systemTextPaint)

            // Unit + Label
            val valueWidth = systemTextPaint.measureText(value)
            systemLabelPaint.textSize = radius * 0.5f
            systemLabelPaint.textAlign = Paint.Align.LEFT
            systemLabelPaint.typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            systemLabelPaint.color = color
            systemLabelPaint.alpha = (180 * breathe).toInt()
            canvas.drawText("$unit $label", textX + valueWidth + radius * 0.15f, cy + radius * 0.15f, systemLabelPaint)
        }

        // Character names to highlight in glow color
        private val highlightWords = setOf(
            "GOKU", "VEGETA", "GOHAN", "GOTEN", "TRUNKS", "PICCOLO",
            "FRIEZA", "FREEZER", "CELL", "BUU", "BILLS", "BEERUS",
            "WHIS", "KRILLIN", "BULMA", "CHICHI", "MR. SATAN", "SATAN",
            "MAJIN BUU", "MAJIN", "GENKI DAMA", "SPIRIT BOMB",
            "SUPER SAIYAN", "GOD", "KAIO", "KAIOUSAMA",
            "CHOU GENKI DAMA", "SAIYAN"
        )

        private fun drawCaption(canvas: Canvas) {
            val text = currentCaption ?: return
            if (text.isEmpty() || surfaceWidth <= 0) return

            // Fade in over 600ms
            val elapsed = System.currentTimeMillis() - lastCaptionChange
            captionAlpha = min(1f, elapsed / 600f)
            val alpha = (captionAlpha * 240).toInt()

            val w = surfaceWidth.toFloat()
            val h = surfaceHeight.toFloat()
            val margin = w * 0.05f
            val maxWidth = w - margin * 2 - w * 0.025f // account for accent bar

            val textSize = w * 0.034f

            // Build word list with highlight info
            data class CaptionWord(val text: String, val highlight: Boolean)
            val rawWords = text.split(" ")
            val captionWords = mutableListOf<CaptionWord>()

            var i = 0
            while (i < rawWords.size) {
                // Check 2-word highlights first (e.g. "MAJIN BUU", "GENKI DAMA")
                var matched = false
                if (i + 1 < rawWords.size) {
                    val twoWord = "${rawWords[i]} ${rawWords[i+1]}"
                    if (highlightWords.contains(twoWord.uppercase())) {
                        captionWords.add(CaptionWord(twoWord, true))
                        i += 2
                        matched = true
                    }
                }
                if (!matched) {
                    val isHighlight = highlightWords.contains(rawWords[i].uppercase().trimEnd(',', '.', '!', '?'))
                    captionWords.add(CaptionWord(rawWords[i], isHighlight))
                    i++
                }
            }

            // Measure and word-wrap
            captionTextPaint.textSize = textSize
            captionTextPaint.typeface = android.graphics.Typeface.DEFAULT

            data class LineWord(val text: String, val highlight: Boolean)
            val lines = mutableListOf<MutableList<LineWord>>()
            var currentLine = mutableListOf<LineWord>()
            var currentWidth = 0f

            for (word in captionWords) {
                captionTextPaint.typeface = if (word.highlight)
                    android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT
                val wordWidth = captionTextPaint.measureText(word.text + " ")
                if (currentWidth + wordWidth > maxWidth && currentLine.isNotEmpty()) {
                    lines.add(currentLine)
                    currentLine = mutableListOf()
                    currentWidth = 0f
                }
                currentLine.add(LineWord(word.text, word.highlight))
                currentWidth += wordWidth
            }
            if (currentLine.isNotEmpty()) lines.add(currentLine)

            val lineHeight = textSize * 1.5f
            val totalTextHeight = lines.size * lineHeight
            val padding = w * 0.03f
            val accentWidth = w * 0.008f

            // Background box
            val boxBottom = h * 0.80f
            val boxTop = boxBottom - totalTextHeight - padding * 2
            val boxLeft = margin - padding
            val boxRight = w - margin + padding

            // Outer glow
            captionBgPaint.color = glowColor
            captionBgPaint.alpha = (alpha * 0.15f).toInt()
            captionBgPaint.maskFilter = BlurMaskFilter(w * 0.02f, BlurMaskFilter.Blur.OUTER)
            canvas.drawRoundRect(
                RectF(boxLeft - 4, boxTop - 4, boxRight + 4, boxBottom + 4),
                w * 0.025f, w * 0.025f, captionBgPaint
            )
            captionBgPaint.maskFilter = null

            // Background
            captionBgPaint.color = Color.BLACK
            captionBgPaint.alpha = (alpha * 0.70f).toInt()
            canvas.drawRoundRect(
                RectF(boxLeft, boxTop, boxRight, boxBottom),
                w * 0.02f, w * 0.02f, captionBgPaint
            )

            // Accent bar on left (glow colored)
            captionBgPaint.color = glowColor
            captionBgPaint.alpha = (alpha * 0.9f).toInt()
            canvas.drawRoundRect(
                RectF(boxLeft + padding * 0.3f, boxTop + padding * 0.6f,
                    boxLeft + padding * 0.3f + accentWidth, boxBottom - padding * 0.6f),
                accentWidth / 2, accentWidth / 2, captionBgPaint
            )

            // Draw text word by word with highlights
            val textLeft = margin + accentWidth + padding * 0.3f
            var y = boxTop + padding + textSize * 1.1f

            for (line in lines) {
                var x = textLeft
                for (word in line) {
                    if (word.highlight) {
                        captionTextPaint.color = glowColor
                        captionTextPaint.typeface = android.graphics.Typeface.DEFAULT_BOLD
                        captionTextPaint.alpha = alpha
                        captionTextPaint.setShadowLayer(6f, 0f, 0f, glowColor)
                    } else {
                        captionTextPaint.color = Color.WHITE
                        captionTextPaint.typeface = android.graphics.Typeface.DEFAULT
                        captionTextPaint.alpha = (alpha * 0.92f).toInt()
                        captionTextPaint.setShadowLayer(3f, 0f, 2f, Color.BLACK)
                    }
                    captionTextPaint.textAlign = Paint.Align.LEFT
                    canvas.drawText(word.text, x, y, captionTextPaint)
                    x += captionTextPaint.measureText(word.text + " ")
                }
                y += lineHeight
            }
        }

        private fun drawEqualizerBars(canvas: Canvas) {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return

            // Smooth levels
            for (i in 0 until BAR_COUNT) {
                val target = currentLevels[i]
                smoothLevels[i] = if (target > smoothLevels[i]) {
                    smoothLevels[i] + (target - smoothLevels[i]) * 0.4f
                } else {
                    smoothLevels[i] + (target - smoothLevels[i]) * 0.25f // faster decay
                }

                if (smoothLevels[i] > peakLevels[i]) {
                    peakLevels[i] = smoothLevels[i]
                    peakDecay[i] = 0f
                } else {
                    peakDecay[i] += 0.003f
                    peakLevels[i] = max(0f, peakLevels[i] - peakDecay[i])
                }
            }

            // Winamp style: segmented blocks
            val totalSegments = 20
            val barSpacing = 3f
            val segmentGap = 2f
            val eqWidth = surfaceWidth * 0.50f
            val barWidth = (eqWidth - barSpacing * (BAR_COUNT - 1)) / BAR_COUNT
            val eqStartX = (surfaceWidth - eqWidth) / 2f
            val maxBarHeight = surfaceHeight * 0.20f
            val bottomY = surfaceHeight - surfaceHeight * 0.035f
            val segmentHeight = (maxBarHeight - segmentGap * (totalSegments - 1)) / totalSegments

            for (i in 0 until BAR_COUNT) {
                val level = smoothLevels[i]
                val idleWave = sin((animationPhase + i * 0.35f).toDouble()).toFloat() * 0.01f + 0.02f
                val effectiveLevel = if (level < 0.01f) idleWave else level
                val litSegments = (effectiveLevel * totalSegments).toInt().coerceIn(0, totalSegments)

                val x = eqStartX + i * (barWidth + barSpacing)

                for (seg in 0 until litSegments) {
                    val segBottom = bottomY - seg * (segmentHeight + segmentGap)
                    val segTop = segBottom - segmentHeight
                    val fraction = seg.toFloat() / (totalSegments - 1)

                    // Winamp colors: green → yellow → red
                    val color = when {
                        fraction < 0.5f -> {
                            // Green to yellow
                            val t = fraction / 0.5f
                            Color.rgb((t * 255).toInt(), 255, 0)
                        }
                        fraction < 0.85f -> {
                            // Yellow to orange
                            val t = (fraction - 0.5f) / 0.35f
                            Color.rgb(255, (255 * (1f - t * 0.5f)).toInt(), 0)
                        }
                        else -> {
                            // Orange to red
                            val t = (fraction - 0.85f) / 0.15f
                            Color.rgb(255, (128 * (1f - t)).toInt(), 0)
                        }
                    }

                    barPaint.shader = null
                    barPaint.color = color
                    canvas.drawRect(x, segTop, x + barWidth, segBottom, barPaint)
                }

                // Peak segment — glowColor with brightness pulse
                if (peakLevels[i] > 0.05f) {
                    val peakSeg = (peakLevels[i] * totalSegments).toInt().coerceIn(0, totalSegments - 1)
                    val peakBottom = bottomY - peakSeg * (segmentHeight + segmentGap)
                    val peakTop = peakBottom - segmentHeight
                    val pulse = (sin((animationPhase * 3f + i).toDouble()).toFloat() * 0.15f + 0.85f)
                    val pr = min(255, (Color.red(glowColor) * pulse + 40).toInt())
                    val pg = min(255, (Color.green(glowColor) * pulse + 40).toInt())
                    val pb = min(255, (Color.blue(glowColor) * pulse + 40).toInt())
                    peakPaint.shader = null
                    peakPaint.color = Color.rgb(pr, pg, pb)
                    canvas.drawRect(x, peakTop, x + barWidth, peakBottom, peakPaint)
                }
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
            releaseVisualizer()
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            drawing = false
            handler.removeCallbacks(drawRunnable)
            releaseVisualizer()
            unregisterBatteryReceiver()
            unregisterPrefsListener()
            wallpaperBitmap?.recycle()
            scaledBitmap?.recycle()
            panoramicBitmap?.recycle()
            super.onDestroy()
        }
    }

    data class GlowDot(val x: Float, val y: Float, val startTime: Long, val color: Int)

    data class RainDrop(
        var x: Float, var y: Float,
        val speed: Float, val length: Float,
        val alpha: Int, val windOffset: Float
    )

    data class GlassDrop(
        var x: Float, var y: Float,
        val radius: Float, val slideSpeed: Float,
        val trailLength: Float, val alpha: Int
    )

    data class CityLight(
        val x: Float, val y: Float,
        val baseAlpha: Int, val flickerSpeed: Float,
        val flickerOffset: Float, val radius: Float,
        val color: Int
    )

    companion object {
        private const val TAG = "PixoraEQ"
        const val GLOW_DURATION = 700L
        const val MAX_RADIUS = 120f
        const val BAR_COUNT = 6
        const val FRAME_DELAY = 42L // ~24fps (saves CPU with equalizer)
        const val IDLE_FRAME_DELAY = 1000L // ~1fps (clock only mode — saves battery)
        const val SILENCE_THRESHOLD = 0.05f
        const val RAIN_DROP_COUNT = 120
        const val GLASS_DROP_COUNT = 15
        const val CITY_LIGHT_COUNT = 35
    }
}
