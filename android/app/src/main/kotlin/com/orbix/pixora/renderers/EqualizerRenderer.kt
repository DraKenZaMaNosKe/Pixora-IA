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

    // ── CLASICO Violet Mist plasma wisps (2026-06-07 v3) ───────────────
    // Replaces the old multi-color spark eruption. ANY bar that peaks past
    // the threshold launches a single purple-magenta plasma WISP — an
    // elongated soft blob that floats upward with a fading trail of past
    // positions. PorterDuff.Mode.ADD blending makes overlapping wisps glow
    // brighter (additive plasma feel). Uses a pre-rendered soft-circle
    // bitmap tinted per particle — no per-frame shader allocation.
    private data class Wisp(
        var x: Float, var y: Float,
        var vx: Float, var vy: Float,
        val baseR: Float,
        // TWO independent hue phases per particle — outer halo cycles
        // through one set of colors while the mid glow shimmers a DIFFERENT
        // hue at the same moment. Combined with random per-particle offsets,
        // every wisp shows a 2-color blend (cyan+pink, magenta+gold, etc),
        // matching the multi-color refraction of a real diamond.
        val colorPhase1: Float,   // outer halo hue
        val colorPhase2: Float,   // mid glow hue (offset from phase1)
        var lifeMs: Long,
        val initialLifeMs: Long,
    )
    private val wisps = ArrayList<Wisp>(96)
    private val lastSparkAtMsPerBar = LongArray(PixoraWallpaperService.BAR_COUNT)
    private var lastSparkFrameMs = 0L
    private val sparkRandom = java.util.Random(1337L)
    // Pre-rendered soft circle (radial gradient white → transparent). Tinted
    // per-frame via ColorFilter — no Shader allocations during draw.
    // 64×64 ARGB_8888 = 16 KB one-time, lazy-init.
    private val softCircleBitmap: Bitmap by lazy {
        val size = 64
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(
                size / 2f, size / 2f, size / 2f,
                intArrayOf(Color.WHITE, Color.argb(180, 255, 255, 255), Color.TRANSPARENT),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP,
            )
        }
        c.drawCircle(size / 2f, size / 2f, size / 2f, p)
        bmp
    }
    private val wispPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.ADD)
    }
    private val wispDst = android.graphics.RectF()
    private val hsvTmp = FloatArray(3)

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
            // BUG FIX 2026-06-07: with the log-spaced mapBarToFFTBin and
            // BAR_COUNT=32 over n=512 bins, bars 0..2 all map to the SAME
            // startBin (1), so startBin == endBin → loop body never runs →
            // those bars stay invisibly at zero. Confirmed by user seeing
            // "missing leftmost bars" + bass-spark spawn at the empty slots.
            // Fix: guarantee at least 1 bin per bar by forcing endBin > startBin.
            val effEnd = kotlin.math.max(endBin, startBin + 1).coerceAtMost(n)
            for (bin in startBin until effEnd) {
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

        // GHOST GRID — draw ALL segments at ~10% alpha BEFORE the lit ones.
        // Gives the iconic Winamp "full LED panel" look where unlit segments
        // are still visible as a faint backdrop. Same color computation as
        // lit segments so they align visually.
        barPaint.shader = null
        for (i in 0 until drawnBars) {
            val x = eqStartX + i * (barWidth + barSpacing)
            for (seg in 0 until totalSegments) {
                val segBottom = bottomY - seg * (segmentHeight + segmentGap)
                val segTop = segBottom - segmentHeight
                val fraction = seg.toFloat() / (totalSegments - 1)
                val ghostColor = when {
                    fraction < 0.60f -> Color.rgb(0x00, 0xFF, 0x41)
                    fraction < 0.85f -> Color.rgb(0xFF, 0xFF, 0x00)
                    else -> Color.rgb(0xFF, 0x15, 0x00)
                }
                barPaint.color = ghostColor
                barPaint.alpha = 22    // ~9% — visible grid, doesn't compete
                canvas.drawRect(x, segTop, x + barWidth, segBottom, barPaint)
            }
        }
        barPaint.alpha = 255  // reset for the lit loop below

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

                // CLASICO 2026-06-07: Winamp 90s gradient — green base for the
                // bottom 60% of each bar, yellow mid 60-85%, red top 85-100%.
                // Matches mockup #81 exactly (the iconic Winamp visualizer).
                val color = when {
                    fraction < 0.60f -> Color.rgb(0x00, 0xFF, 0x41) // green base
                    fraction < 0.85f -> Color.rgb(0xFF, 0xFF, 0x00) // yellow mid
                    else -> Color.rgb(0xFF, 0x15, 0x00)             // red top
                }

                barPaint.shader = null
                barPaint.color = color
                canvas.drawRect(x, segTop, x + barWidth, segBottom, barPaint)
            }

            // Green mirror reflection below the baseline — fades from green
            // at the line to fully transparent at the bottom (Winamp style,
            // mockup #81). Gradient cached in slot 4.
            val mirrorHeight = effectiveLevel * mirrorMaxHeight
            if (mirrorHeight > 1f) {
                ensureGradientCache(bottomY, mirrorMaxHeight)
                barPaint.shader = gradBotCache[4]
                canvas.drawRect(x, bottomY, x + barWidth, bottomY + mirrorHeight, barPaint)
                barPaint.shader = null
            }

            // Peak segment (floating cap) — Winamp peak is solid yellow line
            // that floats above the top lit segment. Fixed color, no glow
            // pulse needed (the iconic Winamp look is flat yellow, not gold).
            if (peakLevels[srcIdx] > 0.05f) {
                val peakSeg = (peakLevels[srcIdx] * totalSegments).toInt().coerceIn(0, totalSegments - 1)
                val peakBottom = bottomY - peakSeg * (segmentHeight + segmentGap)
                val peakTop = peakBottom - segmentHeight
                peakPaint.shader = null
                peakPaint.color = Color.rgb(0xFF, 0xFF, 0x00)
                canvas.drawRect(x, peakTop, x + barWidth, peakBottom, peakPaint)
            }
        }

        // VIOLET MIST PLASMA — wisps spawn from any peaking bar, float up
        // with a fading trail. Additive blending so overlaps glow brighter.
        val nowMs = System.currentTimeMillis()
        maybeTriggerWispSpawns(nowMs, bottomY, maxBarHeight, eqStartX, barWidth, barSpacing)
        updateAndDrawWisps(canvas, nowMs)
    }

    /** Detect a bass-kick event and spawn a fresh spark burst. Bass energy
     *  in FFT actually lives in bins 2-5 (kick drum fundamental ~60-150 Hz),
     *  not bins 0-1 (sub-bass <40 Hz which most music doesn't carry).
     *  Bars 0-1 are visually leftmost but often empty due to the logarithmic
     *  bar-to-bin mapping mapping them to the same FFT bin. We detect on the
     *  bass-rich bands (2..5) and pick the max. Cooldown prevents spam. */
    private fun maybeTriggerWispSpawns(
        nowMs: Long,
        bottomY: Float,
        maxBarHeight: Float,
        eqStartX: Float,
        barWidth: Float,
        barSpacing: Float,
    ) {
        if (!hasAudio) return
        if (wisps.size > 70) return
        val threshold = 0.62f
        val cooldown = 380L
        val totalBars = PixoraWallpaperService.BAR_COUNT
        for (barIdx in 0 until totalBars) {
            val barPower = smoothLevels[barIdx]
            if (barPower < threshold) continue
            if (nowMs - lastSparkAtMsPerBar[barIdx] < cooldown) continue
            val barCenterX = eqStartX + barIdx * (barWidth + barSpacing) + barWidth / 2f
            val barTopY = bottomY - barPower * maxBarHeight - 3f
            spawnWisp(barCenterX, barTopY, barWidth, barPower)
            lastSparkAtMsPerBar[barIdx] = nowMs
        }
    }

    /** Spawn ONE diamond pulse at the given position. Each particle gets a
     *  random [Wisp.colorPhase] (0..1) that drives both its hue cycle (slow
     *  prismatic rotation) and its pulse offset (so coexisting wisps don't
     *  pulse in unison — they breathe independently). */
    private fun spawnWisp(spawnX: Float, spawnY: Float, barWidth: Float, barPower: Float) {
        if (wisps.size > 80) return
        val xJ = (sparkRandom.nextFloat() - 0.5f) * barWidth * 0.6f
        val vx = (sparkRandom.nextFloat() - 0.5f) * 22f
        val vy = -(surfaceWidth * (0.10f + sparkRandom.nextFloat() * 0.10f)) *
                (0.85f + barPower * 0.40f)
        val r = surfaceWidth * (0.011f + sparkRandom.nextFloat() * 0.007f)  // 11..18px on 1080
        val life = 1300L + sparkRandom.nextInt(500).toLong()
        val phase1 = sparkRandom.nextFloat()
        // Phase 2 offset by 0.30..0.65 from phase 1 → guarantees a contrast.
        // 0.30 ≈ ~108° hue gap (e.g. cyan + pink), 0.65 ≈ ~234° (e.g. blue + gold).
        val phase2 = (phase1 + 0.30f + sparkRandom.nextFloat() * 0.35f) % 1f
        wisps.add(Wisp(
            x = spawnX + xJ, y = spawnY,
            vx = vx, vy = vy,
            baseR = r,
            colorPhase1 = phase1,
            colorPhase2 = phase2,
            lifeMs = life, initialLifeMs = life,
        ))
    }

    /** HSV → ARGB. h is 0..1 (will be * 360 internally), s and v 0..1.
     *  Uses a shared FloatArray to avoid allocations on the render path. */
    private fun hsvColor(h: Float, s: Float, v: Float): Int {
        var hf = h
        if (hf < 0) hf = (hf % 1f) + 1f
        if (hf >= 1f) hf %= 1f
        hsvTmp[0] = hf * 360f
        hsvTmp[1] = s
        hsvTmp[2] = v
        return Color.HSVToColor(hsvTmp)
    }

    private fun updateAndDrawWisps(canvas: Canvas, nowMs: Long) {
        if (wisps.isEmpty()) {
            lastSparkFrameMs = nowMs
            return
        }
        val dt = if (lastSparkFrameMs == 0L) 0.016f
                 else ((nowMs - lastSparkFrameMs).toFloat() / 1000f).coerceAtMost(0.1f)
        lastSparkFrameMs = nowMs
        val gravity = surfaceHeight * 0.04f   // barely-there drift downward
        val floorY = surfaceHeight * 0.85f
        val bmp = softCircleBitmap

        for (w in wisps) {
            w.lifeMs -= (dt * 1000).toLong()
            w.vy += gravity * dt
            w.x += w.vx * dt
            w.y += w.vy * dt
        }
        wisps.removeAll { it.lifeMs <= 0 || it.y > floorY }

        // DIAMOND PULSE v2 — 3-layer multi-color gem:
        //   outer halo (hue1) → prismatic tint, low alpha, large radius
        //   mid glow  (hue2) → DIFFERENT hue, brighter, medium radius
        //   bright core      → pure white, small radius (gem facet)
        // Each wisp shows a 2-color blend at any moment + cycles slowly.
        // Different wisps at different phases = the scene has many color
        // pairs simultaneously, like a diamond catching light from many angles.
        val timeSec = nowMs / 1000f
        val cycleSpeed = 0.18f   // ~5.5 sec for a full hue rotation
        for (w in wisps) {
            val lifeFrac = w.lifeMs.toFloat() / w.initialLifeMs.toFloat()
            val pulse = 1f + kotlin.math.sin(
                (nowMs * 0.018f + w.colorPhase1 * 6.2831f).toDouble()
            ).toFloat() * 0.22f
            // Cool-only hue range — cyan(180°) → blue → purple → magenta →
            // pink (350°). Skips red, orange, yellow, green entirely.
            // Matches the user's diamond reference: pink/magenta/purple/blue
            // dominant, NO red/warm tones (those break the gem feel).
            // Raw cycle [0,1] is remapped to [0.50, 0.97] of the HSV wheel.
            // Hue mapping FAVORS cyan(0.50) and hot-pink(0.92) — the two
            // dominant colors in the user's diamond reference. Uses a
            // squaring curve to compress the middle range (purple) and
            // spend more time at the bright extremes.
            val rawHue1 = (w.colorPhase1 + timeSec * cycleSpeed) % 1f
            val rawHue2 = (w.colorPhase2 + timeSec * cycleSpeed) % 1f
            // S-curve via 2 * x * (1-x): output [0,1] biased toward extremes.
            // For x in [0, 1], pull toward 0 or 1 not 0.5.
            val biased1 = if (rawHue1 < 0.5f) rawHue1 * rawHue1 * 2f
                          else 1f - (1f - rawHue1) * (1f - rawHue1) * 2f
            val biased2 = if (rawHue2 < 0.5f) rawHue2 * rawHue2 * 2f
                          else 1f - (1f - rawHue2) * (1f - rawHue2) * 2f
            val hue1 = 0.50f + biased1 * 0.42f   // 0.50..0.92 (cyan..hot pink)
            val hue2 = 0.50f + biased2 * 0.42f
            // Saturation cranked to 0.95 = nearly fully saturated bright
            // colors (matches the vivid diamond reference). Value 1.0 keeps
            // them at max brightness for the additive blend to glow.
            val outerColor = hsvColor(hue1, 0.95f, 1f)
            val midColor   = hsvColor(hue2, 0.92f, 1f)
            val r = w.baseR * pulse
            val baseAlpha = lifeFrac * 255f

            // Outer halo — hue1, large + soft (refraction). Higher alpha
            // (0.45) so the cool color tones actually READ in the scene
            // instead of being washed out by the wallpaper underneath.
            drawTintedSoftCircle(
                canvas, bmp, w.x, w.y, r * 2.4f,
                Color.red(outerColor), Color.green(outerColor), Color.blue(outerColor),
                (baseAlpha * 0.45f).toInt().coerceIn(0, 255),
            )
            // Mid glow — hue2, different color, much brighter (0.72) so the
            // SECOND color is clearly visible alongside the outer halo's hue.
            drawTintedSoftCircle(
                canvas, bmp, w.x, w.y, r * 1.3f,
                Color.red(midColor), Color.green(midColor), Color.blue(midColor),
                (baseAlpha * 0.72f).toInt().coerceIn(0, 255),
            )
            // Bright white core — shrunk slightly (0.55 → 0.45) so the
            // colored halos dominate the visual instead of getting washed
            // out by the white center.
            drawTintedSoftCircle(
                canvas, bmp, w.x, w.y, r * 0.45f,
                255, 255, 255,
                (baseAlpha * 0.90f).toInt().coerceIn(0, 255),
            )
        }
    }

    /** Draws the pre-rendered soft-circle bitmap tinted to (r,g,b) at the
     *  given position with the given radius and overall alpha. Uses the
     *  ADD xfermode on wispPaint for additive plasma glow when wisps overlap. */
    private fun drawTintedSoftCircle(
        canvas: Canvas, bmp: Bitmap,
        x: Float, y: Float, radius: Float,
        r: Int, g: Int, b: Int, alpha: Int,
    ) {
        if (alpha <= 0 || radius <= 0.5f) return
        // MULTIPLY filter tints the white bitmap to the wisp color while
        // preserving the bitmap's own alpha gradient (soft edge).
        wispPaint.colorFilter = android.graphics.PorterDuffColorFilter(
            Color.rgb(r, g, b),
            android.graphics.PorterDuff.Mode.MULTIPLY,
        )
        wispPaint.alpha = alpha
        wispDst.set(x - radius, y - radius, x + radius, y + radius)
        canvas.drawBitmap(bmp, null, wispDst, wispPaint)
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
        // Slot 4 — CLASICO Winamp mirror (was gold). Green fade matches the
        // 90s Winamp visualizer where the mirror below the baseline is the
        // same green as the bar base, fading to transparent.
        gradBotCache[4] = LinearGradient(0f, centerY, 0f, centerY + surfaceHeight * 0.05f,
            Color.argb(140, 0x00, 0xFF, 0x41),
            Color.argb(0, 0x00, 0xFF, 0x41), Shader.TileMode.CLAMP)
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
        // Sine wave overlay removed 2026-06-08 per user request — was the
        // faint white wave drawn over the cyan bars. The bars alone read
        // cleaner as a CRT visualizer.
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
        private const val TRAIL_LEN = 6
    }
}
