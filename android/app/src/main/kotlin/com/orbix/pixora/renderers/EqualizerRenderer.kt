package com.orbix.pixora.renderers

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.*
import android.media.audiofx.Visualizer
import android.util.Log
import androidx.core.content.ContextCompat
import com.orbix.pixora.PixoraWallpaperService
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

class EqualizerRenderer(private val context: Context? = null) {

    interface AudioCallback {
        fun onAudioStarted()
    }

    private val visualizerLock = Object()
    private var visualizer: Visualizer? = null
    @Volatile private var isReleasing = false
    private val currentLevels = FloatArray(PixoraWallpaperService.BAR_COUNT)
    val smoothLevels = FloatArray(PixoraWallpaperService.BAR_COUNT)
    private val peakLevels = FloatArray(PixoraWallpaperService.BAR_COUNT)
    private val peakDecay = FloatArray(PixoraWallpaperService.BAR_COUNT)
    @Volatile var hasAudio = false
        private set
    var silentFrames = 0

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val peakPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    // Cached cyber-glitch satellite paints — were allocated as Paint(barPaint)
    // copies 3× per bar per frame (~2880 alloc/s with BAR_COUNT=32 at 30fps).
    private val cyberRedDim = Paint(Paint.ANTI_ALIAS_FLAG).apply { alpha = 80 }
    private val cyberCyanDim = Paint(Paint.ANTI_ALIAS_FLAG).apply { alpha = 80 }
    private val cyberYellowDim = Paint(Paint.ANTI_ALIAS_FLAG).apply { alpha = 140 }
    // Per-bar gradient cache — invalidated only when surfaceHeight changes.
    // Was rebuilding 1920 gradients/sec across Grok/CRT/Aurora/Crystal styles.
    private val gradTopCache = arrayOfNulls<Shader>(64)   // top half (mirror styles)
    private val gradBotCache = arrayOfNulls<Shader>(64)   // bottom mirror
    private var gradCachedForHeight = -1
    // Pre-seeded Random for flame flicker — was hitting global Math.random()
    // with contention on the render thread.
    private val flameRandom = java.util.Random(42L)

    var surfaceWidth = 0
    var surfaceHeight = 0
    var glowColor = Color.parseColor("#C9A650")
    var animationPhase = 0f

    /** Active HUD preset — controls eq style/colors. Defaults to SACRED (current gold). */
    var currentPreset: HudPreset = HudPreset.CLASICO

    /** Device performance tier — controls per-bar setShadowLayer (which is the
     *  single biggest perf killer on Mali GPUs / mid-range Samsung). When
     *  [DeviceTier.useBarShadow] is false we skip the shadow ENTIRELY in
     *  Aurora/Gemini and let the gradient fill carry the visual weight. */
    var tier: DeviceTier = DeviceTier.MID

    var audioCallback: AudioCallback? = null

    fun setupVisualizer() {
        // Check RECORD_AUDIO permission before creating Visualizer
        if (context != null &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "RECORD_AUDIO permission not granted, skipping visualizer")
            return
        }
        // IDEMPOTENT — fixes a long-standing bug where every visibility=true
        // (which fires every time the user returns to home from any app)
        // would RELEASE the working Visualizer and try to recreate it. The
        // recreate often failed with "setCaptureSize called in wrong state: 2"
        // because of stale native effect state from the just-released instance.
        // Result: EQ stuck in idle marquee, no audio reaction. Symptom that
        // surfaced after 2026-06-06 perf overhaul — but the bug was pre-existing.
        synchronized(visualizerLock) {
            try {
                if (visualizer != null && visualizer?.enabled == true) {
                    Log.d(TAG, "Visualizer already running — skip re-setup")
                    return
                }
            } catch (_: Exception) { /* fall through and recreate */ }
        }
        releaseVisualizer()
        synchronized(visualizerLock) {
            isReleasing = false
            try {
                val viz = Visualizer(0)
                viz.captureSize = Visualizer.getCaptureSizeRange()[1]
                Log.d(TAG, "Visualizer captureSize=${viz.captureSize}")

                viz.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(v: Visualizer?, waveform: ByteArray?, samplingRate: Int) {}
                    override fun onFftDataCapture(v: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                        if (isReleasing) return
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
    }

    private fun processFFT(fft: ByteArray) {
        if (isReleasing) return
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
        val maxLevel = currentLevels.max()
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
        synchronized(visualizerLock) {
            isReleasing = true
            try {
                visualizer?.let { it.enabled = false; it.release() }
            } catch (_: Exception) {}
            visualizer = null
            currentLevels.fill(0f)
            hasAudio = false
        }
    }

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return

        // Smooth levels + peak tracking — tuned 2026-06-04 for snappier attack
        // (real VU meter feel). Rise 0.75 reaches 90% of target in ~2 frames at
        // 30fps (~66ms total latency above the 50ms FFT capture window). Fall
        // 0.35 is a controlled decay that avoids jitter without feeling sluggish.
        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            val target = currentLevels[i]
            smoothLevels[i] = if (target > smoothLevels[i]) {
                smoothLevels[i] + (target - smoothLevels[i]) * 0.75f  // snappy attack
            } else {
                smoothLevels[i] + (target - smoothLevels[i]) * 0.35f  // smooth fall
            }

            if (smoothLevels[i] > peakLevels[i]) {
                peakLevels[i] = smoothLevels[i]
                peakDecay[i] = 0f
            } else {
                peakDecay[i] += 0.005f  // peak falls faster than before (was 0.003)
                peakLevels[i] = max(0f, peakLevels[i] - peakDecay[i])
            }
        }

        // Dispatch to preset-specific renderer (2026-06-06: slimmed to 4 presets)
        when (currentPreset.eqStyle) {
            EqStyle.GOLD_SEGMENTED -> { /* fall through to CLASICO code below */ }
            EqStyle.GROK_SPECTRUM -> { drawGrokSpectrum(canvas); return }
            EqStyle.CRT_BARS -> { drawCrtBars(canvas); return }
            EqStyle.CYBER_GLITCH -> { drawCyberGlitch(canvas); return }
        }

        // SACRED v2 (2026-06-05): segmented gold bars positioned ABOVE the dock
        // (was overlapping into the dock area) + subtle gold mirror reflection
        // for premium depth. Wider canvas (88% vs 50%) takes advantage of the
        // new BAR_COUNT=32.
        // Perf (2026-06-06): visibleBars = tier.visibleBars (32 HIGH / 20 MID /
        // 12 LOW). FFT still processes 32 bands but we only draw N of them by
        // sampling smoothLevels at stride BAR_COUNT/N. Wider bars, same EQ
        // width, ~38% fewer rect draws on MID.
        val totalSegments = 14
        val barSpacing = 3f
        val segmentGap = 2f
        val eqWidth = surfaceWidth * 0.88f
        val drawnBars = tier.visibleBars
        val barWidth = (eqWidth - barSpacing * (drawnBars - 1)) / drawnBars
        val eqStartX = (surfaceWidth - eqWidth) / 2f
        // Bars top half rises ABOVE this baseline; mirror falls below.
        val bottomY = surfaceHeight * 0.85f
        val maxBarHeight = surfaceHeight * 0.10f
        val mirrorMaxHeight = surfaceHeight * 0.05f
        val segmentHeight = (maxBarHeight - segmentGap * (totalSegments - 1)) / totalSegments

        for (i in 0 until drawnBars) {
            // Sample the FFT band centered for this visible bar. With 32 bands
            // and N=20 visible, bar 10 reads band 16, etc. Spread is roughly
            // logarithmic from the FFT mapping so we still cover bass→treble.
            val srcIdx = (i * PixoraWallpaperService.BAR_COUNT / drawnBars)
                .coerceIn(0, PixoraWallpaperService.BAR_COUNT - 1)
            val level = smoothLevels[srcIdx]
            // Dramatic marquee wave when idle (no music) — primary wave flows
            // left→right, secondary wave counter-flows for an organic dual-pattern
            // motion. Amplitude 0.50 (was 0.01) so the wallpaper feels alive
            // even without audio. Real audio data takes over when music plays.
            // Marquee uses srcIdx (FFT band index 0..31) so the wave pattern
            // spreads across the full bar range regardless of how many bars
            // we actually draw. With i 0..19 and BAR_COUNT=32 norm in marquee
            // would be 0..0.61 → wave envelope collapsed to the left side.
            val effectiveLevel = if (hasAudio) level else idleMarqueeLevel(srcIdx)
            val litSegments = (effectiveLevel * totalSegments).toInt().coerceIn(0, totalSegments)

            val x = eqStartX + i * (barWidth + barSpacing)

            for (seg in 0 until litSegments) {
                val segBottom = bottomY - seg * (segmentHeight + segmentGap)
                val segTop = segBottom - segmentHeight
                val fraction = seg.toFloat() / (totalSegments - 1)

                // gold-deep → gold → gold-bright (replaces Winamp green→yellow→red).
                val color = when {
                    fraction < 0.5f -> {
                        val t = fraction / 0.5f
                        val r = (0x8A + (0xC9 - 0x8A) * t).toInt()
                        val g = (0x6F + (0xA6 - 0x6F) * t).toInt()
                        val b = (0x33 + (0x50 - 0x33) * t).toInt()
                        Color.rgb(r, g, b)
                    }
                    else -> {
                        val t = (fraction - 0.5f) / 0.5f
                        val r = (0xC9 + (0xF0 - 0xC9) * t).toInt()
                        val g = (0xA6 + (0xDD - 0xA6) * t).toInt()
                        val b = (0x50 + (0x9E - 0x50) * t).toInt()
                        Color.rgb(r, g, b)
                    }
                }

                barPaint.shader = null
                barPaint.color = color
                canvas.drawRect(x, segTop, x + barWidth, segBottom, barPaint)
            }

            // Gold mirror reflection below the baseline — fades from gold-30%
            // alpha at the line to fully transparent at the bottom. Adds depth
            // without visual noise (premium feel). Gradient cached, see slot 4.
            val mirrorHeight = effectiveLevel * mirrorMaxHeight
            if (mirrorHeight > 1f) {
                ensureGradientCache(bottomY, mirrorMaxHeight)
                barPaint.shader = gradBotCache[4]
                canvas.drawRect(x, bottomY, x + barWidth, bottomY + mirrorHeight, barPaint)
                barPaint.shader = null
            }

            // Peak segment (floating cap) — read from srcIdx so it tracks the
            // same FFT band as the bar's level.
            if (peakLevels[srcIdx] > 0.05f) {
                val peakSeg = (peakLevels[srcIdx] * totalSegments).toInt().coerceIn(0, totalSegments - 1)
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

    /** Modern Mono / Winamp classic mirror — segmented bars rising UP from the
     *  vertical center, with a faded mirror copy growing DOWN. Colors mimic
     *  the iconic Winamp 90s gradient: green base → yellow mid → red top.
     *  Peak indicator (yellow line) floats above each top bar. */
    private fun drawWinampMirror(canvas: Canvas) {
        val totalSegments = 12
        val barSpacing = 3f
        val segmentGap = 2f
        val eqWidth = surfaceWidth * 0.88f
        val barWidth = (eqWidth - barSpacing * (PixoraWallpaperService.BAR_COUNT - 1)) /
                PixoraWallpaperService.BAR_COUNT
        val eqStartX = (surfaceWidth - eqWidth) / 2f
        // EQ positioned near the BOTTOM — center line at 85% height so the
        // mirror (10% bottom half) sits just above the dock area at ~95%.
        val centerY = surfaceHeight * 0.85f
        val maxHalfHeight = surfaceHeight * 0.08f
        val segmentHeight = (maxHalfHeight - segmentGap * (totalSegments - 1)) / totalSegments

        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            val effectiveLevel = effectiveAudioLevel(i)
            val litSegments = (effectiveLevel * totalSegments).toInt().coerceIn(0, totalSegments)
            val x = eqStartX + i * (barWidth + barSpacing)

            // Top — green→yellow→red Winamp gradient
            for (seg in 0 until litSegments) {
                val segBottom = centerY - seg * (segmentHeight + segmentGap)
                val segTop = segBottom - segmentHeight
                val fraction = seg.toFloat() / max(1, totalSegments - 1)
                val color = when {
                    fraction < 0.5f -> Color.rgb(0x00, 0xFF, 0x41)         // green
                    fraction < 0.8f -> Color.rgb(0xFF, 0xFF, 0x00)         // yellow
                    else -> Color.rgb(0xFF, 0x15, 0x00)                    // red
                }
                barPaint.shader = null
                barPaint.color = color
                canvas.drawRect(x, segTop, x + barWidth, segBottom, barPaint)
            }

            // Mirror bottom — same shape, green fading to transparent
            for (seg in 0 until litSegments) {
                val segTop = centerY + seg * (segmentHeight + segmentGap)
                val segBottom = segTop + segmentHeight
                val fadeAlpha = (255 * 0.55f * (1f - seg.toFloat() / litSegments)).toInt()
                    .coerceIn(0, 255)
                barPaint.shader = null
                barPaint.color = Color.argb(fadeAlpha, 0x00, 0xFF, 0x41)
                canvas.drawRect(x, segTop, x + barWidth, segBottom, barPaint)
            }

            // Peak floating cap (yellow line above top bar)
            if (peakLevels[i] > 0.05f) {
                val peakSeg = (peakLevels[i] * totalSegments).toInt().coerceIn(0, totalSegments - 1)
                val peakBottom = centerY - peakSeg * (segmentHeight + segmentGap) - segmentHeight
                peakPaint.shader = null
                peakPaint.color = Color.rgb(0xFF, 0xFF, 0x00)
                canvas.drawRect(x, peakBottom - 2f, x + barWidth, peakBottom, peakPaint)
            }
        }
    }

    /** Idle marquee — when no music is playing, drive the bars with a flowing
     *  dual-wave so the wallpaper still feels alive. Primary wave moves
     *  left→right (phase + i), secondary counter-flows (phase - i) for an
     *  organic, never-quite-repeating pattern. Amplitude tuned (~0.50 max) so
     *  bars are clearly visible but not screaming "music!" when none plays. */
    private fun idleMarqueeLevel(i: Int): Float {
        val primary = (sin((animationPhase * 1.4f + i * 0.30f).toDouble()).toFloat() * 0.5f + 0.5f) // 0..1
        val secondary = sin((animationPhase * 0.7f - i * 0.18f).toDouble()).toFloat() * 0.3f       // -0.3..+0.3
        // Centre-tapered envelope so the wave looks like a soft pulse moving
        // through the bar field rather than a flat bar.
        val norm = if (PixoraWallpaperService.BAR_COUNT > 1)
            i.toFloat() / (PixoraWallpaperService.BAR_COUNT - 1)
        else 0.5f
        val env = 0.6f + 0.4f * (1f - kotlin.math.abs(norm - 0.5f) * 1.4f).coerceIn(0f, 1f)
        // Floor lifted 0.05 -> 0.10 (2026-06-06): with 14 segments per bar the
        // truncation (level * 14).toInt() rounded any value below 1/14 (~0.072)
        // to zero, leaving GAPS in the idle marquee. 0.10 guarantees every bar
        // shows at least 1 segment so the EQ never has visible holes.
        return ((primary * 0.55f + secondary * 0.20f) * env).coerceIn(0.10f, 0.65f)
    }

    /** Common "audio-or-idle" level used by all preset draw methods.
     *  Reads smoothLevels directly here — DO NOT call back into self. */
    private fun effectiveAudioLevel(i: Int): Float {
        return if (hasAudio) smoothLevels[i].coerceAtLeast(0.04f) else idleMarqueeLevel(i)
    }

    /** Re-build the gradient cache when surface height changes. Each preset
     *  picks a slot 0..6 (one per gradient style) and we cache top + mirror
     *  for that slot. Called from draw() before dispatching to a style. */
    private fun ensureGradientCache(centerY: Float, maxHalf: Float) {
        if (gradCachedForHeight == surfaceHeight) return
        gradCachedForHeight = surfaceHeight
        // Slot 0 — Grok spectrum top (cyan→green→yellow→orange)
        gradTopCache[0] = LinearGradient(0f, centerY - maxHalf, 0f, centerY,
            intArrayOf(Color.parseColor("#FF6B35"), Color.parseColor("#FFFB00"),
                Color.parseColor("#00FF85"), Color.parseColor("#00E5FF")),
            floatArrayOf(0f, 0.4f, 0.8f, 1f), Shader.TileMode.CLAMP)
        gradBotCache[0] = LinearGradient(0f, centerY, 0f, centerY + maxHalf * 0.85f,
            Color.argb(180, 0, 229, 255), Color.argb(0, 0, 229, 255), Shader.TileMode.CLAMP)
        // Slot 1 — Aurora top
        gradTopCache[1] = LinearGradient(0f, centerY - maxHalf, 0f, centerY,
            intArrayOf(Color.parseColor("#B83BCB"), Color.parseColor("#00C2FF"),
                Color.parseColor("#00FFAA")),
            floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
        gradBotCache[1] = LinearGradient(0f, centerY, 0f, centerY + maxHalf * 0.9f,
            Color.argb(150, 0, 255, 170), Color.argb(0, 184, 59, 203), Shader.TileMode.CLAMP)
        // Slot 2 — CRT bars (top-down cyan)
        gradTopCache[2] = LinearGradient(0f, centerY - maxHalf, 0f, centerY + maxHalf,
            Color.parseColor("#00E5FF"), Color.argb(30, 0, 229, 255), Shader.TileMode.CLAMP)
        // Slot 3 — Flame gradient (anchored at bottom)
        gradTopCache[3] = LinearGradient(0f, centerY - maxHalf, 0f, centerY + maxHalf,
            intArrayOf(Color.parseColor("#FFD700"), Color.parseColor("#FF8C00"),
                Color.parseColor("#FF4500"), Color.argb(80, 139, 0, 0)),
            floatArrayOf(0f, 0.4f, 0.85f, 1f), Shader.TileMode.CLAMP)
        // Slot 4 — Sacred gold mirror
        gradBotCache[4] = LinearGradient(0f, centerY, 0f, centerY + surfaceHeight * 0.05f,
            Color.argb(110, 0xE6, 0xB6, 0x55),
            Color.argb(0, 0xE6, 0xB6, 0x55), Shader.TileMode.CLAMP)
    }

    // ── Helper: standard mirror layout shared by several presets ──────────
    private fun eqLayout(): EqLayout {
        val barSpacing = 3f
        val eqWidth = surfaceWidth * 0.88f
        val barWidth = (eqWidth - barSpacing * (PixoraWallpaperService.BAR_COUNT - 1)) /
                PixoraWallpaperService.BAR_COUNT
        val eqStartX = (surfaceWidth - eqWidth) / 2f
        // EQ near bottom — center line at 85% so mirror sits above the dock.
        val centerY = surfaceHeight * 0.85f
        val maxHalfHeight = surfaceHeight * 0.08f
        return EqLayout(barSpacing, barWidth, eqStartX, centerY, maxHalfHeight)
    }
    private data class EqLayout(val barSpacing: Float, val barWidth: Float,
        val eqStartX: Float, val centerY: Float, val maxHalfHeight: Float)

    // ── 03 · GEMINI DOTS — 5 small colored circles at bottom, pulse with music
    private fun drawGeminiDots(canvas: Canvas) {
        // Position near bottom (same line as other EQs at 85% height)
        val centerY = surfaceHeight * 0.85f
        val N = 5
        val totalW = surfaceWidth * 0.50f
        val gap = totalW / (N - 1)
        val startX = (surfaceWidth - totalW) / 2
        val colors = intArrayOf(
            Color.parseColor("#4285F4"), Color.parseColor("#EA4335"),
            Color.parseColor("#FBBC04"), Color.parseColor("#34A853"),
            Color.parseColor("#4285F4"),
        )
        // Sample 5 frequency bands evenly across the BAR_COUNT (32) bins —
        // bass / low-mid / mid / high-mid / treble. Each dot pulses with its
        // band's energy. smoothLevels already has the snappy attack from the
        // 0.75 rise factor so visuals feel live.
        val barStep = PixoraWallpaperService.BAR_COUNT / N
        val baseR = surfaceWidth * 0.012f       // ~13 px on 1080
        val maxAmp = surfaceWidth * 0.020f      // up to +22 px when v=1
        for (i in 0 until N) {
            val v = effectiveAudioLevel(i * barStep).coerceIn(0f, 1f)
            val r = baseR + v * maxAmp
            barPaint.apply {
                color = colors[i]
                shader = null
                // Glow scales with r so big-pulse dots have proportional bloom.
                // Per-circle shadowLayer is the perf killer on Mali GPUs — only
                // enable on HIGH tier. On MID/LOW the saturated colors + size
                // pulse carry enough visual energy without the bloom.
                if (tier.useBarShadow) {
                    setShadowLayer(r * 1.2f, 0f, 0f, colors[i])
                } else {
                    setShadowLayer(0f, 0f, 0f, 0)
                }
                alpha = 255
            }
            canvas.drawCircle(startX + i * gap, centerY, r, barPaint)
        }
        barPaint.setShadowLayer(0f, 0f, 0f, 0)
    }

    // ── 04 · GROK SPECTRUM — bars cyan→green→yellow→orange + mirror ──────
    private fun drawGrokSpectrum(canvas: Canvas) {
        val l = eqLayout()
        ensureGradientCache(l.centerY, l.maxHalfHeight)
        val gTop = gradTopCache[0]; val gBot = gradBotCache[0]
        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            val v = effectiveAudioLevel(i)
            val topH = v * l.maxHalfHeight
            val botH = v * l.maxHalfHeight * 0.85f
            val x = l.eqStartX + i * (l.barWidth + l.barSpacing)
            barPaint.shader = gTop
            canvas.drawRoundRect(x, l.centerY - topH, x + l.barWidth, l.centerY,
                l.barWidth/2, l.barWidth/2, barPaint)
            barPaint.shader = gBot
            canvas.drawRoundRect(x, l.centerY, x + l.barWidth, l.centerY + botH,
                l.barWidth/2, l.barWidth/2, barPaint)
        }
        barPaint.shader = null
    }

    // ── 05 · CRT BARS — cyan bars with horizontal wave overlay ──────────
    private fun drawCrtBars(canvas: Canvas) {
        val l = eqLayout()
        ensureGradientCache(l.centerY, l.maxHalfHeight)
        val cachedGrad = gradTopCache[2]
        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            val v = effectiveAudioLevel(i)
            val h = v * l.maxHalfHeight * 1.7f
            val x = l.eqStartX + i * (l.barWidth + l.barSpacing)
            barPaint.shader = cachedGrad
            canvas.drawRect(x, l.centerY + l.maxHalfHeight - h, x + l.barWidth, l.centerY + l.maxHalfHeight, barPaint)
            barPaint.shader = null
            barPaint.color = Color.parseColor("#00FFFF")
            canvas.drawRect(x, l.centerY + l.maxHalfHeight - h, x + l.barWidth, l.centerY + l.maxHalfHeight - h + 3f, barPaint)
        }
        // Sine wave overlay
        peakPaint.apply { color = Color.argb(140, 255, 255, 255); strokeWidth = 1.5f; style = Paint.Style.STROKE; setShadowLayer(0f, 0f, 0f, 0) }
        val path = Path()
        for (x in 0..surfaceWidth step 4) {
            val y = l.centerY + sin((animationPhase * 3f + x * 0.04f).toDouble()).toFloat() * l.maxHalfHeight * 0.4f
            if (x == 0) path.moveTo(x.toFloat(), y) else path.lineTo(x.toFloat(), y)
        }
        canvas.drawPath(path, peakPaint)
        peakPaint.style = Paint.Style.FILL
    }

    // ── 07 · FLAME — tapered bars like flames, taller in center, flicker ──
    private fun drawFlameBars(canvas: Canvas) {
        val l = eqLayout()
        ensureGradientCache(l.centerY, l.maxHalfHeight)
        val cachedGrad = gradTopCache[3]
        val bottomY = l.centerY + l.maxHalfHeight
        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            var v = effectiveAudioLevel(i)
            val centerBoost = 1f - kotlin.math.abs(
                (i.toFloat() / (PixoraWallpaperService.BAR_COUNT - 1)) - 0.5f) * 1.4f
            v *= kotlin.math.max(0.3f, centerBoost) * (0.85f + (flameRandom.nextFloat() * 0.3f))
            val h = v * l.maxHalfHeight * 1.7f
            val x = l.eqStartX + i * (l.barWidth + l.barSpacing)
            barPaint.shader = cachedGrad
            val path = Path()
            path.moveTo(x + l.barWidth * 0.3f, bottomY)
            path.quadTo(x, bottomY - h * 0.5f, x + l.barWidth * 0.4f, bottomY - h)
            path.quadTo(x + l.barWidth * 0.5f, bottomY - h * 1.05f, x + l.barWidth * 0.6f, bottomY - h)
            path.quadTo(x + l.barWidth, bottomY - h * 0.5f, x + l.barWidth * 0.7f, bottomY)
            path.close()
            canvas.drawPath(path, barPaint)
        }
        barPaint.shader = null
    }

    // ── 08 · AURORA RIBBONS — pill-shaped bars with aurora gradient + mirror
    private fun drawAuroraRibbons(canvas: Canvas) {
        val l = eqLayout()
        ensureGradientCache(l.centerY, l.maxHalfHeight)
        val gTop = gradTopCache[1]; val gBot = gradBotCache[1]
        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            val v = effectiveAudioLevel(i)
            val topH = v * l.maxHalfHeight
            val botH = v * l.maxHalfHeight * 0.9f
            val x = l.eqStartX + i * (l.barWidth + l.barSpacing)
            barPaint.apply {
                shader = gTop
                // Per-bar shadowLayer = the single most expensive op on Mali
                // GPUs. With BAR_COUNT=32 this fires 32× per frame and forces
                // software rendering for that paint. Skip on MID/LOW; the
                // aurora gradient itself stays vivid.
                if (tier.useBarShadow) {
                    setShadowLayer(8f, 0f, 0f, Color.parseColor("#00FFAA"))
                } else {
                    setShadowLayer(0f, 0f, 0f, 0)
                }
            }
            canvas.drawRoundRect(x, l.centerY - topH, x + l.barWidth, l.centerY,
                l.barWidth, l.barWidth, barPaint)
            barPaint.setShadowLayer(0f, 0f, 0f, 0)
            barPaint.shader = gBot
            canvas.drawRoundRect(x, l.centerY, x + l.barWidth, l.centerY + botH,
                l.barWidth, l.barWidth, barPaint)
        }
        barPaint.shader = null
    }

    // ── 09 · CYBER GLITCH — yellow bars with RGB offset on peaks ──────────
    private fun drawCyberGlitch(canvas: Canvas) {
        val l = eqLayout()
        // Pre-config dim paints once (was allocating Paint(barPaint) 3× per bar)
        cyberRedDim.color = Color.parseColor("#FF003C"); cyberRedDim.alpha = 80
        cyberCyanDim.color = Color.parseColor("#00FFEA"); cyberCyanDim.alpha = 80
        cyberYellowDim.color = Color.parseColor("#FCEE0A"); cyberYellowDim.alpha = 140
        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            val v = effectiveAudioLevel(i)
            val topH = v * l.maxHalfHeight
            val botH = v * l.maxHalfHeight * 0.85f
            val x = l.eqStartX + i * (l.barWidth + l.barSpacing)
            val off = if (v > 0.7f) 2f else 0f
            barPaint.shader = null
            barPaint.color = Color.parseColor("#FF003C")
            canvas.drawRect(x - off, l.centerY - topH, x + l.barWidth - off, l.centerY, barPaint)
            canvas.drawRect(x - off, l.centerY, x + l.barWidth - off, l.centerY + botH, cyberRedDim)
            barPaint.color = Color.parseColor("#00FFEA")
            canvas.drawRect(x + off, l.centerY - topH, x + l.barWidth + off, l.centerY, barPaint)
            canvas.drawRect(x + off, l.centerY, x + l.barWidth + off, l.centerY + botH, cyberCyanDim)
            barPaint.color = Color.parseColor("#FCEE0A")
            canvas.drawRect(x, l.centerY - topH, x + l.barWidth, l.centerY, barPaint)
            canvas.drawRect(x, l.centerY, x + l.barWidth, l.centerY + botH, cyberYellowDim)
        }
    }

    // ── 10 · CRYSTAL SHARDS — translucent prismatic bars with mirror ─────
    private fun drawCrystalShards(canvas: Canvas) {
        val l = eqLayout()
        for (i in 0 until PixoraWallpaperService.BAR_COUNT) {
            val v = effectiveAudioLevel(i)
            val topH = v * l.maxHalfHeight
            val botH = v * l.maxHalfHeight * 0.85f
            val x = l.eqStartX + i * (l.barWidth + l.barSpacing)
            val g = LinearGradient(x, 0f, x + l.barWidth, 0f,
                intArrayOf(Color.argb(140, 255, 100, 150),
                    Color.argb(165, 150, 200, 255),
                    Color.argb(140, 255, 200, 255)),
                floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
            barPaint.shader = g
            canvas.drawRect(x, l.centerY - topH, x + l.barWidth, l.centerY, barPaint)
            peakPaint.apply {
                color = Color.argb(180, 255, 255, 255); strokeWidth = 0.5f; style = Paint.Style.STROKE
                setShadowLayer(0f, 0f, 0f, 0)
            }
            canvas.drawRect(x, l.centerY - topH, x + l.barWidth, l.centerY, peakPaint)
            peakPaint.style = Paint.Style.FILL
            barPaint.alpha = 128
            canvas.drawRect(x, l.centerY, x + l.barWidth, l.centerY + botH, barPaint)
            barPaint.alpha = 255
        }
        barPaint.shader = null
    }

    companion object {
        private const val TAG = "PixoraEQ"
    }
}
