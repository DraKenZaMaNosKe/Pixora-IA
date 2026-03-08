package com.orbix.pixora

import android.graphics.*
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.util.Log
import android.view.MotionEvent
import android.view.SurfaceHolder
import java.io.File
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

        // Pre-allocated paints (avoid GC pressure)
        private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val peakPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val overlayPaint = Paint()
        private val glowDotPaint = Paint(Paint.ANTI_ALIAS_FLAG)

        private val drawRunnable = object : Runnable {
            override fun run() {
                if (drawing) {
                    drawFrame()
                    handler.postDelayed(this, FRAME_DELAY)
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

            // Stop draw loop when no audio and no touch glow
            if (!hasAudio && glowDots.isEmpty()) {
                silentFrames++
                // Wait 30 frames (~1.5s) after silence to let bars animate down
                if (silentFrames > 30) {
                    drawing = false
                    handler.removeCallbacks(drawRunnable)
                    // Draw one last frame with clean background
                    val h = surfaceHolder
                    var c: Canvas? = null
                    try {
                        c = h.lockCanvas()
                        if (c != null) drawBackground(c)
                    } finally {
                        if (c != null) try { h.unlockCanvasAndPost(c) } catch (_: Exception) {}
                    }
                }
            } else {
                silentFrames = 0
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
        const val SILENCE_THRESHOLD = 0.02f
    }
}
