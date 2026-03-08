package com.orbix.pixora

import android.graphics.*
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
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
            Log.d(TAG, "Engine onCreate")
        }

        private fun loadWallpaperImage() {
            try {
                val prefs = applicationContext.getSharedPreferences("pixora_live", 0)
                val path = prefs.getString("wallpaper_path", null)
                val color = prefs.getString("glow_color", "#7C4DFF")

                color?.let {
                    try { glowColor = Color.parseColor(it) } catch (_: Exception) {}
                }

                // Pick clock style based on wallpaper path hash
                clockStyle = abs((path ?: "").hashCode()) % 4

                if (path != null) {
                    val file = File(path)
                    if (file.exists()) {
                        wallpaperBitmap = BitmapFactory.decodeFile(path)
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        private fun createScaledBitmap() {
            val bmp = wallpaperBitmap ?: return
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return

            Thread {
                val srcRatio = bmp.width.toFloat() / bmp.height.toFloat()
                val dstRatio = surfaceWidth.toFloat() / surfaceHeight.toFloat()

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
                } catch (e: Exception) {
                    Log.e(TAG, "createScaledBitmap error: ${e.message}")
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
                    drawClock(canvas)
                    drawEqualizerBars(canvas)
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
            if (!hasAudio && glowDots.isEmpty()) {
                silentFrames++
                if (silentFrames > 30 && !idleMode) {
                    idleMode = true
                }
            } else {
                silentFrames = 0
                if (idleMode) {
                    idleMode = false
                }
            }
        }

        private fun drawBackground(canvas: Canvas) {
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

        private fun drawEqualizerBars(canvas: Canvas) {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return

            // Smooth levels
            for (i in 0 until BAR_COUNT) {
                val target = currentLevels[i]
                smoothLevels[i] = if (target > smoothLevels[i]) {
                    smoothLevels[i] + (target - smoothLevels[i]) * 0.4f
                } else {
                    smoothLevels[i] + (target - smoothLevels[i]) * 0.12f
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
            wallpaperBitmap?.recycle()
            scaledBitmap?.recycle()
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
        const val IDLE_FRAME_DELAY = 100L // ~10fps (clock only mode)
        const val SILENCE_THRESHOLD = 0.02f
    }
}
