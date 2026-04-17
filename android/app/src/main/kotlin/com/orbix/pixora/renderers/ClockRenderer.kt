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

    // Pre-allocated Typefaces to avoid allocation per frame
    private val typefaceBold = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    private val typefaceLight = Typeface.create("sans-serif-light", Typeface.NORMAL)
    private val typefaceBoldBold = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)

    var clockStyle = 0
    private var lastMinute = -1
    private var lastHour = -1
    private var hourFlashAlpha = 0f
    private var cachedGradientShader: LinearGradient? = null
    private var cachedGradientGlowColor = 0

    var surfaceWidth = 0
    var surfaceHeight = 0
    var glowColor = Color.parseColor("#7C4DFF")
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

        // --- Hour change flash effect ---
        // Only trigger when:
        //   1. The hour actually changed (hour != lastHour)
        //   2. It wasn't the first frame after init (lastHour >= 0)
        //   3. We're within the first minute of the new hour (minute <= 1)
        //      This prevents the flash from firing when the user unlocks their
        //      phone 20 minutes after the hour changed — the effect only makes
        //      sense if the user sees it "live" at :00.
        if (hour != lastHour && lastHour >= 0 && minute <= 1) {
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
                    typeface = typefaceBold
                    textAlign = Paint.Align.CENTER
                    letterSpacing = 0.08f
                    alpha = 80
                    setShadowLayer(50f, 0f, 0f, glowColor)
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
                    setShadowLayer(30f, 0f, 0f, glowColor)
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
                    setShadowLayer(8f, 0f, 2f, Color.argb(100, 0, 0, 0))
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
            typeface = typefaceBoldBold
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
}
