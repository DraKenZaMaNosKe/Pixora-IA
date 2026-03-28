package com.orbix.pixora.renderers

import android.graphics.*
import android.media.audiofx.Visualizer
import android.util.Log
import com.orbix.pixora.PixoraWallpaperService
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

class EqualizerRenderer {

    interface AudioCallback {
        fun onAudioStarted()
    }

    private var visualizer: Visualizer? = null
    private val currentLevels = FloatArray(PixoraWallpaperService.BAR_COUNT)
    val smoothLevels = FloatArray(PixoraWallpaperService.BAR_COUNT)
    private val peakLevels = FloatArray(PixoraWallpaperService.BAR_COUNT)
    private val peakDecay = FloatArray(PixoraWallpaperService.BAR_COUNT)
    var hasAudio = false
        private set
    var silentFrames = 0

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val peakPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    var surfaceWidth = 0
    var surfaceHeight = 0
    var glowColor = Color.parseColor("#7C4DFF")
    var animationPhase = 0f

    var audioCallback: AudioCallback? = null

    fun setupVisualizer() {
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
        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
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
        hasAudio = maxLevel > PixoraWallpaperService.SILENCE_THRESHOLD

        // Clear levels immediately when music stops (avoid ghost bars)
        if (!hasAudio && wasPlaying) {
            currentLevels.fill(0f)
        }

        // Wake up draw loop when music starts
        if (hasAudio && !wasPlaying) {
            silentFrames = 0
            audioCallback?.onAudioStarted()
        }
    }

    private fun mapBarToFFTBin(barIndex: Int, totalBins: Int): Int {
        val logMin = ln(1.0)
        val logMax = ln(totalBins.toDouble())
        val fraction = barIndex.toDouble() / PixoraWallpaperService.BAR_COUNT
        return exp(logMin + fraction * (logMax - logMin)).toInt().coerceIn(1, totalBins)
    }

    fun releaseVisualizer() {
        try {
            visualizer?.let { it.enabled = false; it.release() }
        } catch (_: Exception) {}
        visualizer = null
        currentLevels.fill(0f)
        hasAudio = false
    }

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        // Smooth levels
        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            val target = currentLevels[i]
            smoothLevels[i] = if (target > smoothLevels[i]) {
                smoothLevels[i] + (target - smoothLevels[i]) * 0.4f
            } else {
                smoothLevels[i] + (target - smoothLevels[i]) * 0.25f
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
        val barWidth = (eqWidth - barSpacing * (PixoraWallpaperService.BAR_COUNT - 1)) / PixoraWallpaperService.BAR_COUNT
        val eqStartX = (surfaceWidth - eqWidth) / 2f
        val maxBarHeight = surfaceHeight * 0.20f
        val bottomY = surfaceHeight - surfaceHeight * 0.035f
        val segmentHeight = (maxBarHeight - segmentGap * (totalSegments - 1)) / totalSegments

        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            val level = smoothLevels[i]
            val idleWave = sin((animationPhase + i * 0.35f).toDouble()).toFloat() * 0.01f + 0.02f
            val effectiveLevel = if (level < 0.01f) idleWave else level
            val litSegments = (effectiveLevel * totalSegments).toInt().coerceIn(0, totalSegments)

            val x = eqStartX + i * (barWidth + barSpacing)

            for (seg in 0 until litSegments) {
                val segBottom = bottomY - seg * (segmentHeight + segmentGap)
                val segTop = segBottom - segmentHeight
                val fraction = seg.toFloat() / (totalSegments - 1)

                // Winamp colors: green -> yellow -> red
                val color = when {
                    fraction < 0.5f -> {
                        val t = fraction / 0.5f
                        Color.rgb((t * 255).toInt(), 255, 0)
                    }
                    fraction < 0.85f -> {
                        val t = (fraction - 0.5f) / 0.35f
                        Color.rgb(255, (255 * (1f - t * 0.5f)).toInt(), 0)
                    }
                    else -> {
                        val t = (fraction - 0.85f) / 0.15f
                        Color.rgb(255, (128 * (1f - t)).toInt(), 0)
                    }
                }

                barPaint.shader = null
                barPaint.color = color
                canvas.drawRect(x, segTop, x + barWidth, segBottom, barPaint)
            }

            // Peak segment
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

    companion object {
        private const val TAG = "PixoraEQ"
    }
}
