package com.orbix.pixora.renderers

import android.graphics.*
import android.text.TextPaint
import java.util.Calendar
import java.util.Locale
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

class ClockRenderer {

    private val clockTimePaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val clockDatePaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val clockShadowPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val clockSecPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val clockArcPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val clockFlashPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    // Pre-allocated Typefaces. Black & Gold uses SERIF ITALIC to evoke
    // Cormorant Garamond / Playfair (not in system fonts — Typeface.SERIF
    // maps to Noto Serif which is a good transitional serif).
    private val typefaceBold = Typeface.create(Typeface.SERIF, Typeface.ITALIC)
    private val typefaceLight = Typeface.create(Typeface.SERIF, Typeface.ITALIC)
    private val typefaceBoldBold = Typeface.create(Typeface.SERIF, Typeface.BOLD_ITALIC)

    // Modern Mono preset typefaces — sans-serif ultra-light (Roboto Thin weight 100
    // on API 28+; falls back to regular sans-serif on older). Approximates Manrope
    // without needing to bundle a font asset.
    private val typefaceModernTime: Typeface = if (android.os.Build.VERSION.SDK_INT >= 28) {
        Typeface.create(Typeface.SANS_SERIF, 100, false)
    } else {
        Typeface.SANS_SERIF
    }
    private val typefaceModernMono: Typeface = Typeface.MONOSPACE

    var clockStyle = 0
    /** Active HUD preset. SACRED uses the original 4 serif styles + arc + dots;
     *  any other preset uses a generic "preset-driven" layout that reads the
     *  font/color/size/glow from [HudPreset]. */
    var currentPreset: HudPreset = HudPreset.CLASICO

    /** Device performance tier — controls shadow radius via [DeviceTier.shadowMultiplier].
     *  Set by [com.orbix.pixora.PixoraWallpaperService] on engine creation.
     *  Default MID is safe for unknown devices. See DeviceTier.kt for why. */
    var tier: DeviceTier = DeviceTier.MID

    /** Scaled shadow radius helper — applies tier multiplier so a 50px blur
     *  becomes ~8px on LOW, ~20px on MID, full 50px on HIGH. */
    private fun Float.scaledShadow(): Float = this * tier.shadowMultiplier
    private var lastMinute = -1
    private var lastHour = -1
    private var hourFlashAlpha = 0f
    private var cachedGradientShader: LinearGradient? = null
    private var cachedGradientGlowColor = 0

    // ── HH:MM Bitmap cache (2026-06-06 perf overhaul) ──────────────────────
    // The Sacred clock renders serif italic text with a 50px shadowLayer per
    // frame. setShadowLayer on TextPaint is the single most expensive paint
    // op on Mali GPUs (forces software rendering for that draw call). HH:MM
    // only changes once per minute, so we pre-render to a Bitmap when the
    // minute ticks and blit it every frame (free on hardware Canvas).
    // Re-render triggers: minute change · style change · surface resize ·
    // shadow multiplier change (tier flip).
    private var cachedTimeBitmap: Bitmap? = null
    private var cachedTimeMinute: Int = -1
    private var cachedTimeStyle: Int = -1
    private var cachedTimeSize: Float = -1f
    private var cachedTimeStr: String = ""
    private var cachedTimeShadowMul: Float = -1f
    private var cachedTimeAscent: Float = 0f
    private val cachedTimePad: Float = 80f  // halo padding so 50px blur fits

    var surfaceWidth = 0
    var surfaceHeight = 0

    // Black & Gold: the clock uses ONE color (gold) regardless of what the
    // WallpaperService passes in. The `glowColor` setter is retained for API
    // compat but is effectively a no-op — the getter always returns gold.
    private val _fixedGold = Color.parseColor("#C9A650")
    var glowColor: Int
        get() = _fixedGold
        set(_) {} // intentionally ignored — no per-wallpaper adaptation
    var animationPhase = 0f

    fun draw(canvas: Canvas) {
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

        // Non-Sacred preset → simpler preset-driven layout. SACRED falls through
        // to the original arc + breath + dots + 4 serif styles below.
        if (currentPreset != HudPreset.CLASICO) {
            drawWithPreset(canvas, timeStr, secStr, dayName, dayNum, monthName)
            lastHour = hour
            lastMinute = minute
            return
        }

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
            val speed = 3f + (10 - secsLeft) * 0.7f
            (sin(animationPhase * speed.toDouble()).toFloat() * 0.5f + 0.5f)
        } else 1f

        // Hour-change flash effect intentionally DISABLED on 2026-04-19 —
        // user disliked the gold whole-screen flash at :00 of every hour.
        // lastHour still tracked so future logic can re-introduce if needed.
        lastHour = hour

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

        // PERF (2026-06-06): on tier MID/LOW, blit pre-rendered HH:MM bitmap
        // instead of running the heavy shadowLayer text path each frame. Only
        // skip cache during countdown (last 10s of each minute) when alpha
        // pulses per frame. ~83% of frames save the expensive render.
        if (tier.useClockTextCache && !isCountdown) {
            val bmp = ensureTimeCache(timeStr, timeSize, clockStyle)
            // Blit so the text baseline lands exactly on timeY. The cache
            // bitmap draws its baseline at row (pad - ascent), so the bitmap
            // top-left Y is: timeY - (pad - ascent) = timeY - pad + ascent.
            // ascent is negative so this naturally goes above timeY.
            canvas.drawBitmap(
                bmp,
                centerX - bmp.width / 2f,
                timeY - cachedTimePad + cachedTimeAscent,
                null
            )
        } else when (clockStyle) {
            0 -> { // Neon Glow
                clockShadowPaint.apply {
                    color = glowColor
                    textSize = timeSize
                    typeface = typefaceBold
                    textAlign = Paint.Align.CENTER
                    letterSpacing = 0.08f
                    alpha = 80
                    setShadowLayer(50f.scaledShadow(), 0f, 0f, glowColor)
                }
                canvas.drawText(timeStr, centerX, timeY, clockShadowPaint)
                clockTimePaint.apply {
                    color = Color.WHITE
                    textSize = timeSize
                    typeface = typefaceBold
                    textAlign = Paint.Align.CENTER
                    letterSpacing = 0.08f
                    alpha = timeAlpha
                    shader = null
                    setShadowLayer(30f.scaledShadow(), 0f, 0f, glowColor)
                }
                canvas.drawText(timeStr, centerX, timeY, clockTimePaint)
            }
            1 -> { // Clean Minimal
                clockTimePaint.apply {
                    color = Color.WHITE
                    textSize = timeSize * 0.9f
                    typeface = typefaceLight
                    textAlign = Paint.Align.CENTER
                    letterSpacing = 0.12f
                    alpha = timeAlpha
                    shader = null
                    setShadowLayer(8f.scaledShadow(), 0f, 2f, Color.argb(100, 0, 0, 0))
                }
                canvas.drawText(timeStr, centerX, timeY, clockTimePaint)
            }
            2 -> { // Bold Shadow
                clockShadowPaint.apply {
                    color = glowColor
                    textSize = timeSize * 1.05f
                    typeface = typefaceBold
                    textAlign = Paint.Align.CENTER
                    letterSpacing = 0.02f
                    alpha = 150
                    setShadowLayer(0f, 0f, 0f, 0)
                }
                canvas.drawText(timeStr, centerX + 4f, timeY + 4f, clockShadowPaint)
                clockTimePaint.apply {
                    color = Color.WHITE
                    textSize = timeSize * 1.05f
                    typeface = typefaceBold
                    textAlign = Paint.Align.CENTER
                    letterSpacing = 0.02f
                    alpha = timeAlpha
                    shader = null
                    setShadowLayer(0f, 0f, 0f, 0)
                }
                canvas.drawText(timeStr, centerX, timeY, clockTimePaint)
            }
            3 -> { // Gradient Fade
                if (cachedGradientShader == null || cachedGradientGlowColor != glowColor) {
                    cachedGradientShader = LinearGradient(
                        centerX - timeSize, timeY - timeSize * 0.8f,
                        centerX + timeSize, timeY,
                        intArrayOf(Color.WHITE, glowColor), null, Shader.TileMode.CLAMP
                    )
                    cachedGradientGlowColor = glowColor
                }
                clockTimePaint.apply {
                    textSize = timeSize
                    typeface = typefaceBold
                    textAlign = Paint.Align.CENTER
                    letterSpacing = 0.06f
                    alpha = timeAlpha
                    shader = cachedGradientShader
                    setShadowLayer(15f.scaledShadow(), 0f, 0f, Color.argb(100, 0, 0, 0))
                }
                canvas.drawText(timeStr, centerX, timeY, clockTimePaint)
                clockTimePaint.shader = null
            }
        }

        // --- Seconds — SACRED v2 (2026-06-05) ---
        // Previously cycled colors HSV-style (disconnected from brand);
        // now a refined gold integrated with the time text.
        val secColor = glowColor
        val secGlowColor = Color.argb(100, Color.red(glowColor), Color.green(glowColor), Color.blue(glowColor))

        // Seconds text - right of time with subtle breathing glow
        val timeWidth = clockTimePaint.measureText(timeStr)
        val secX = centerX + timeWidth / 2 + surfaceWidth * 0.025f

        clockSecPaint.apply {
            color = secColor
            textSize = secSize * 0.85f
            typeface = typefaceBoldBold
            textAlign = Paint.Align.LEFT
            letterSpacing = 0.03f
            val breathe = sin(animationPhase * 1.5).toFloat() * 4f + 6f
            setShadowLayer(breathe.scaledShadow(), 0f, 0f, secGlowColor)
        }
        canvas.drawText(secStr, secX, timeY, clockSecPaint)

        // --- Sacred divider ◆ — gold line + diamond between time and date ---
        val dividerY = timeY + surfaceHeight * 0.022f
        val dividerHalf = surfaceWidth * 0.07f
        clockArcPaint.apply {
            style = Paint.Style.STROKE
            strokeWidth = 0.8f
            color = glowColor
            alpha = 130
            shader = null
            setShadowLayer(0f, 0f, 0f, 0)
        }
        // Two gradient fade lines on either side of the diamond
        clockArcPaint.alpha = 90
        canvas.drawLine(centerX - dividerHalf, dividerY, centerX - dividerHalf * 0.18f, dividerY, clockArcPaint)
        canvas.drawLine(centerX + dividerHalf * 0.18f, dividerY, centerX + dividerHalf, dividerY, clockArcPaint)
        // Diamond ◆ filled at center
        clockArcPaint.apply { style = Paint.Style.FILL; alpha = 180 }
        val diamondR = surfaceWidth * 0.008f
        val diamondPath = android.graphics.Path().apply {
            moveTo(centerX, dividerY - diamondR)
            lineTo(centerX + diamondR, dividerY)
            lineTo(centerX, dividerY + diamondR)
            lineTo(centerX - diamondR, dividerY)
            close()
        }
        canvas.drawPath(diamondPath, clockArcPaint)

        // --- Date — SACRED v2: bigger Cormorant italic gold ---
        clockDatePaint.apply {
            textSize = dateSize * 1.25f
            textAlign = Paint.Align.CENTER
            letterSpacing = 0.20f
            typeface = typefaceLight
            shader = null
            setShadowLayer(6f.scaledShadow(), 0f, 0f, Color.argb(80, 0, 0, 0))
            color = when (clockStyle) {
                0 -> { // Neon: glow colored date
                    setShadowLayer(10f.scaledShadow(), 0f, 0f, glowColor)
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

    /** Preset-driven clock layout — uses font/color/size/glow from [HudPreset].
     *  Time centered top, date row below. No arc, no breath, no ms dots (those
     *  are SACRED-specific embellishments). Each preset's typography + glow
     *  creates its distinct identity. */
    private fun drawWithPreset(
        canvas: Canvas,
        timeStr: String,
        secStr: String,
        dayName: String,
        dayNum: Int,
        monthName: String,
    ) {
        // Defensive reset — clockShadowPaint may still carry a 50f shadow
        // radius from the SACRED Neon Glow path if the user toggled presets
        // mid-session. Drawing with stale shadow state would leak a halo
        // around any future text that uses this paint.
        clockShadowPaint.setShadowLayer(0f, 0f, 0f, 0)
        val preset = currentPreset
        val centerX = surfaceWidth / 2f
        val timeY = surfaceHeight * 0.18f
        val timeSize = surfaceWidth * preset.clockSizeMult

        clockTimePaint.apply {
            color = preset.clockColor
            textSize = timeSize
            typeface = preset.clockFont
            textAlign = Paint.Align.CENTER
            letterSpacing = preset.clockLetterSpacing
            alpha = 255
            shader = null
            if (preset.clockGlowRadius > 0) {
                setShadowLayer(preset.clockGlowRadius.scaledShadow(), 0f, 4f, preset.clockGlowColor)
            } else {
                setShadowLayer(0f, 0f, 0f, 0)
            }
        }
        canvas.drawText(timeStr, centerX, timeY, clockTimePaint)

        // Cyber Glitch — draw RGB-split copies behind the main time text
        if (preset == HudPreset.CYBER) {
            val splitOff = timeSize * 0.04f
            clockTimePaint.apply {
                color = Color.parseColor("#FF003C")
                setShadowLayer(0f, 0f, 0f, 0)
            }
            canvas.drawText(timeStr, centerX + splitOff, timeY, clockTimePaint)
            clockTimePaint.color = Color.parseColor("#00FFEA")
            canvas.drawText(timeStr, centerX - splitOff, timeY, clockTimePaint)
            clockTimePaint.color = preset.clockColor
            clockTimePaint.setShadowLayer(preset.clockGlowRadius.scaledShadow(), 0f, 4f, preset.clockGlowColor)
            canvas.drawText(timeStr, centerX, timeY, clockTimePaint)
        }

        // Date row — small monospace below
        val dateShort = "${dayName.take(3).uppercase()} ${"%02d".format(dayNum)} ${monthName.take(3).uppercase()}"
        val dateSize = surfaceWidth * 0.028f
        val dateY = timeY + surfaceHeight * 0.05f
        clockDatePaint.apply {
            color = Color.argb(190,
                Color.red(preset.clockColor), Color.green(preset.clockColor), Color.blue(preset.clockColor))
            textSize = dateSize
            typeface = Typeface.MONOSPACE
            textAlign = Paint.Align.CENTER
            letterSpacing = 0.18f
            shader = null
            setShadowLayer(4f.scaledShadow(), 0f, 1f, Color.argb(140, 0, 0, 0))
        }
        val dateText = "$dateShort   :$secStr"
        canvas.drawText(dateText, centerX, dateY, clockDatePaint)
    }

    /**
     * Pre-renders HH:MM (with its style-specific shadow halo) to a Bitmap and
     * returns it. Subsequent frames within the same minute can blit the bitmap
     * in O(1) instead of re-running serif text + 50px shadowLayer (the single
     * biggest paint cost on Mali GPUs).
     *
     * Cache key: minute + clockStyle + timeSize + shadowMultiplier + timeStr.
     * If any changes, regenerate. Also stores text width + ascent so the
     * caller can position the bitmap precisely and position the :SS digit
     * to the right of it.
     */
    private fun ensureTimeCache(timeStr: String, timeSize: Float, style: Int): Bitmap {
        val minute = Calendar.getInstance().get(Calendar.MINUTE)
        val mul = tier.shadowMultiplier
        val existing = cachedTimeBitmap
        if (existing != null
            && !existing.isRecycled
            && cachedTimeMinute == minute
            && cachedTimeStyle == style
            && cachedTimeSize == timeSize
            && cachedTimeStr == timeStr
            && cachedTimeShadowMul == mul) {
            return existing
        }

        // Configure paint with this style's typeface + size FIRST so we can
        // measure the text and compute the bitmap dimensions.
        val (tf, ls, ss) = when (style) {
            0 -> Triple(typefaceBold, 0.08f, 1.00f)   // Neon Glow
            1 -> Triple(typefaceLight, 0.12f, 0.90f)  // Clean Minimal
            2 -> Triple(typefaceBold, 0.02f, 1.05f)   // Bold Shadow
            3 -> Triple(typefaceBold, 0.06f, 1.00f)   // Gradient Fade
            else -> Triple(typefaceBold, 0.05f, 1.00f)
        }
        clockTimePaint.typeface = tf
        clockTimePaint.textSize = timeSize * ss
        clockTimePaint.letterSpacing = ls
        clockTimePaint.textAlign = Paint.Align.CENTER
        clockTimePaint.shader = null
        clockTimePaint.setShadowLayer(0f, 0f, 0f, 0)
        val textWidth = clockTimePaint.measureText(timeStr)
        val fm = clockTimePaint.fontMetrics
        val textHeight = fm.descent - fm.ascent
        // Padding = max shadow radius for this style (≤50f × shadowMul). Add
        // a 6px safety so bordering anti-alias never clips.
        val w = (textWidth + cachedTimePad * 2 + 6f).toInt().coerceAtLeast(1)
        val h = (textHeight + cachedTimePad * 2 + 6f).toInt().coerceAtLeast(1)

        existing?.recycle()
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val bc = Canvas(bmp)
        val bcx = w / 2f
        val bcy = cachedTimePad - fm.ascent  // baseline inside bitmap

        // Re-render the style — identical to the inline path. We avoid sharing
        // the inline code (extracting + branching) because the inline path
        // sometimes draws TWO text passes (shadow underlay + bright fill)
        // which both must hit the bitmap.
        when (style) {
            0 -> { // Neon Glow — shadow underlay + WHITE fill with 30px halo
                clockShadowPaint.apply {
                    color = glowColor; textSize = timeSize; typeface = typefaceBold
                    textAlign = Paint.Align.CENTER; letterSpacing = 0.08f; alpha = 80
                    setShadowLayer(50f.scaledShadow(), 0f, 0f, glowColor)
                }
                bc.drawText(timeStr, bcx, bcy, clockShadowPaint)
                clockTimePaint.apply {
                    color = Color.WHITE; alpha = 255; shader = null
                    setShadowLayer(30f.scaledShadow(), 0f, 0f, glowColor)
                }
                bc.drawText(timeStr, bcx, bcy, clockTimePaint)
            }
            1 -> { // Clean Minimal — single pass with subtle drop shadow
                clockTimePaint.apply {
                    color = Color.WHITE; alpha = 255; shader = null
                    setShadowLayer(8f.scaledShadow(), 0f, 2f, Color.argb(100, 0, 0, 0))
                }
                bc.drawText(timeStr, bcx, bcy, clockTimePaint)
            }
            2 -> { // Bold Shadow — solid gold offset behind + white in front
                clockShadowPaint.apply {
                    color = glowColor; textSize = timeSize * 1.05f
                    typeface = typefaceBold; textAlign = Paint.Align.CENTER
                    letterSpacing = 0.02f; alpha = 150
                    setShadowLayer(0f, 0f, 0f, 0)
                }
                bc.drawText(timeStr, bcx + 4f, bcy + 4f, clockShadowPaint)
                clockTimePaint.apply {
                    color = Color.WHITE; alpha = 255; shader = null
                    setShadowLayer(0f, 0f, 0f, 0)
                }
                bc.drawText(timeStr, bcx, bcy, clockTimePaint)
            }
            3 -> { // Gradient Fade — gradient shader applied to text
                val grad = LinearGradient(
                    bcx - timeSize, bcy - timeSize * 0.8f,
                    bcx + timeSize, bcy,
                    intArrayOf(Color.WHITE, glowColor), null, Shader.TileMode.CLAMP
                )
                clockTimePaint.apply {
                    alpha = 255; shader = grad
                    setShadowLayer(15f.scaledShadow(), 0f, 0f, Color.argb(100, 0, 0, 0))
                }
                bc.drawText(timeStr, bcx, bcy, clockTimePaint)
                clockTimePaint.shader = null
            }
        }

        cachedTimeBitmap = bmp
        cachedTimeMinute = minute
        cachedTimeStyle = style
        cachedTimeSize = timeSize
        cachedTimeStr = timeStr
        cachedTimeShadowMul = mul
        cachedTimeAscent = fm.ascent  // negative; used by drawBitmap offset calc
        return bmp
    }
}
