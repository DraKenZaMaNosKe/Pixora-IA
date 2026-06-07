package com.orbix.pixora.renderers

import android.app.ActivityManager
import android.content.Context
import android.graphics.*
import android.os.Environment
import android.os.StatFs
import android.text.TextPaint
import kotlin.math.sin

class SystemRingsRenderer(private val context: Context) {

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
    private val ringRect = RectF()
    private val typefaceCondensedBold = Typeface.create("sans-serif-condensed", Typeface.BOLD)
    private val typefaceLight = Typeface.create("sans-serif-light", Typeface.NORMAL)
    // Cached at class init — was previously allocated every frame in drawMiniRing,
    // creating ~60 native objects/sec and GC churn on low-RAM devices.
    private val sacredDashEffect = android.graphics.DashPathEffect(floatArrayOf(4f, 3f), 0f)

    var surfaceWidth = 0
    var surfaceHeight = 0
    var glowColor = Color.parseColor("#C9A650")

    // User-controlled toggles (set by PixoraWallpaperService from SharedPreferences).
    var showRam = true
    var showStorage = true

    /** Device performance tier — controls halo fill + shadow radius on the
     *  ring arc. On LOW we skip the halo glow entirely (still draw arc +
     *  dashed circle). See DeviceTier.kt. */
    var tier: DeviceTier = DeviceTier.MID

    private fun readSystemInfo() {
        val now = System.currentTimeMillis()
        if (now - lastSystemRead < 5000) return
        lastSystemRead = now

        try {
            // RAM
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
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

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        if (!showRam && !showStorage) return
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
        val startY = batteryY + batteryRadius * 2.8f

        val ringRadius = w * 0.04f
        val spacing = ringRadius * 3.2f
        val leftX = ringRadius + w * 0.055f

        // --- RAM Ring ---
        if (showRam) {
            val ramPct = if (ramTotalGB > 0) ((ramTotalGB - ramAvailableGB) / ramTotalGB * 100f) else 0f
            val ramColor = when {
                ramPct > 90 -> Color.parseColor("#8A6F33")
                ramPct > 75 -> Color.parseColor("#F0DD9E")
                else -> glowColor
            }
            drawMiniRing(
                canvas, leftX, startY, ringRadius,
                ramPct, ramColor, breathe,
                String.format("%.1f", ramAvailableGB), "GB", "RAM"
            )
        }

        // --- Storage Ring ---
        // If RAM is hidden, pull the storage ring up into its slot so we don't leave
        // a gap where RAM used to be.
        if (showStorage) {
            val storageY = if (showRam) startY + spacing else startY
            val storagePct = if (storageTotalGB > 0) ((storageTotalGB - storageAvailableGB) / storageTotalGB * 100f) else 0f
            val storageColor = when {
                storagePct > 90 -> Color.parseColor("#8A6F33")
                storagePct > 75 -> Color.parseColor("#F0DD9E")
                else -> glowColor
            }
            drawMiniRing(
                canvas, leftX, storageY, ringRadius,
                storagePct, storageColor, breathe,
                if (storageAvailableGB >= 10) String.format("%.0f", storageAvailableGB)
                else String.format("%.1f", storageAvailableGB),
                "GB", "DISK"
            )
        }
    }

    private fun drawMiniRing(
        canvas: Canvas, cx: Float, cy: Float, radius: Float,
        usedPct: Float, color: Int, breathe: Float,
        value: String, unit: String, label: String
    ) {
        val strokeWidth = radius * 0.25f

        // SACRED v2 (2026-06-05): dashed rotating circle OUTSIDE the ring —
        // adds sacred-geometry motion. Outer circle at +6dp, dashed pattern
        // 4dp on / 3dp off, rotated by animationPhase (slow). Cached
        // DashPathEffect — see class init.
        // SCOPING NOTE: this renderer is currently only invoked when the
        // active HudPreset is SACRED (GOLD_RINGS style). If a future preset
        // reuses SystemRingsRenderer for a different identity, gate this
        // dashed-circle block behind a `var isSacred: Boolean = true` flag.
        val dashRadius = radius + strokeWidth * 1.6f
        systemRingBgPaint.style = Paint.Style.STROKE
        systemRingBgPaint.strokeWidth = 1f
        systemRingBgPaint.color = color
        systemRingBgPaint.alpha = 110
        systemRingBgPaint.pathEffect = sacredDashEffect
        canvas.save()
        canvas.rotate(systemPulsePhase * 4f, cx, cy)
        canvas.drawCircle(cx, cy, dashRadius, systemRingBgPaint)
        canvas.restore()
        systemRingBgPaint.pathEffect = null

        // Background ring
        systemRingBgPaint.style = Paint.Style.STROKE
        systemRingBgPaint.strokeWidth = strokeWidth
        systemRingBgPaint.strokeCap = Paint.Cap.ROUND
        systemRingBgPaint.color = Color.argb(40, 255, 255, 255)
        ringRect.set(cx - radius, cy - radius, cx + radius, cy + radius)
        canvas.drawArc(ringRect, -90f, 360f, false, systemRingBgPaint)

        // Halo glow — soft radial fill behind the ring. Cheap-ish but adds up
        // when both RAM + DISK rings draw. Skip on LOW tier.
        if (tier.useRingHaloFill) {
            systemRingBgPaint.style = Paint.Style.FILL
            systemRingBgPaint.color = Color.argb((30 * breathe).toInt(),
                Color.red(color), Color.green(color), Color.blue(color))
            canvas.drawCircle(cx, cy, dashRadius * 0.95f, systemRingBgPaint)
        }

        // Colored arc
        val sweep = usedPct * 3.6f
        systemRingPaint.style = Paint.Style.STROKE
        systemRingPaint.strokeWidth = strokeWidth
        systemRingPaint.strokeCap = Paint.Cap.ROUND
        systemRingPaint.color = color
        systemRingPaint.alpha = (255 * breathe).toInt()
        // Shadow on the arc — tier-scaled. On MID this drops from radius*0.4
        // to radius*0.16 (~60% cheaper). On LOW it's ~radius*0.06 (basically
        // off but still hints depth).
        systemRingPaint.setShadowLayer((radius * 0.4f) * tier.shadowMultiplier, 0f, 0f, color)
        canvas.drawArc(ringRect, -90f, sweep, false, systemRingPaint)
        systemRingPaint.clearShadowLayer()

        // Value text (right of ring)
        val textX = cx + radius + strokeWidth + radius * 0.4f
        systemTextPaint.textSize = radius * 0.85f
        systemTextPaint.textAlign = Paint.Align.LEFT
        systemTextPaint.typeface = typefaceCondensedBold
        systemTextPaint.color = Color.WHITE
        systemTextPaint.alpha = (220 * breathe).toInt()
        canvas.drawText(value, textX, cy + radius * 0.15f, systemTextPaint)

        // Unit + Label
        val valueWidth = systemTextPaint.measureText(value)
        systemLabelPaint.textSize = radius * 0.5f
        systemLabelPaint.textAlign = Paint.Align.LEFT
        systemLabelPaint.typeface = typefaceLight
        systemLabelPaint.color = color
        systemLabelPaint.alpha = (180 * breathe).toInt()
        canvas.drawText("$unit $label", textX + valueWidth + radius * 0.15f, cy + radius * 0.15f, systemLabelPaint)
    }
}
