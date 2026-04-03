package com.orbix.pixora.renderers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.*
import android.os.BatteryManager
import android.text.TextPaint
import kotlin.math.sin

class BatteryIndicator(private val context: Context) {

    private var batteryLevel = -1
    private var batteryCharging = false
    private var batteryPulsePhase = 0f
    private val batteryArcPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val batteryBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val batteryTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val batteryIconPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var batteryReceiver: BroadcastReceiver? = null
    private val typefaceLightBold = Typeface.create("sans-serif-light", Typeface.BOLD)

    var surfaceWidth = 0
    var surfaceHeight = 0
    var glowColor = Color.parseColor("#7C4DFF")

    fun registerBatteryReceiver() {
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
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
        context.registerReceiver(batteryReceiver, filter)
    }

    fun unregisterBatteryReceiver() {
        batteryReceiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        batteryReceiver = null
    }

    fun draw(canvas: Canvas) {
        if (batteryLevel < 0 || surfaceWidth <= 0 || surfaceHeight <= 0) return

        val w = surfaceWidth.toFloat()
        val h = surfaceHeight.toFloat()

        // Position: top-left area
        val radius = w * 0.055f
        val centerX = radius + w * 0.05f
        val centerY = h * 0.12f
        val strokeWidth = radius * 0.22f

        val r = Color.red(glowColor)
        val g = Color.green(glowColor)
        val b = Color.blue(glowColor)

        val arcColor = when {
            batteryLevel <= 15 -> Color.rgb(255, 50, 50)
            batteryLevel <= 30 -> Color.rgb(255, 165, 0)
            else -> glowColor
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
        val sweepAngle = batteryLevel * 3.6f
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
        batteryTextPaint.typeface = typefaceLightBold
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

    fun release() {
        unregisterBatteryReceiver()
    }
}
