package com.orbix.pixora.renderers

import android.app.ActivityManager
import android.content.Context
import android.content.IntentFilter
import android.graphics.*
import android.os.BatteryManager
import android.os.Environment
import android.os.StatFs
import android.text.TextPaint
import kotlin.math.min
import kotlin.math.sin

/**
 * Multi-style HUD renderer — replaces the old MiniHudRenderer. Dispatches
 * to a draw method per [HudStyle]. Reads system info (battery/RAM/disk)
 * every 5s and caches values to keep per-frame cost minimal.
 *
 * [HudStyle.GOLD_RINGS] is NOT handled here — it stays in the original
 * [SystemRingsRenderer] for compatibility. PixoraWallpaperService picks
 * which renderer to call based on the active preset.
 */
class HudRenderer(private val context: Context) {

    private var batteryPct = 0
    private var ramUsedPct = 0
    private var diskUsedPct = 0
    private var lastRead = 0L

    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val labelPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shapePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val hexPath = Path()
    private val shardPath = Path()

    var surfaceWidth = 0
    var surfaceHeight = 0
    var animationPhase = 0f

    var hudStyle: HudStyle = HudStyle.HORIZONTAL_METERS
    var accentColor: Int = Color.rgb(0x00, 0xFF, 0x41)
    var showRam = true
    var showStorage = true

    private fun refreshIfNeeded() {
        val now = System.currentTimeMillis()
        if (now - lastRead < 5000) return
        lastRead = now
        try {
            val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            batteryPct = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 0
            if (batteryPct == 0) {
                val intent = context.registerReceiver(null, IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
                val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                if (level >= 0 && scale > 0) batteryPct = (level * 100 / scale)
            }
        } catch (_: Exception) {}
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            am?.let {
                val mi = ActivityManager.MemoryInfo()
                it.getMemoryInfo(mi)
                if (mi.totalMem > 0)
                    ramUsedPct = (((mi.totalMem - mi.availMem) * 100f) / mi.totalMem).toInt()
            }
        } catch (_: Exception) {}
        try {
            val stat = StatFs(Environment.getDataDirectory().absolutePath)
            val total = stat.blockCountLong * stat.blockSizeLong
            val avail = stat.availableBlocksLong * stat.blockSizeLong
            if (total > 0) diskUsedPct = (((total - avail) * 100f) / total).toInt()
        } catch (_: Exception) {}
    }

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        refreshIfNeeded()
        val rows = buildList {
            add(Triple("BAT", batteryPct, batteryColor(batteryPct)))
            if (showRam) add(Triple("RAM", ramUsedPct, usageColor(ramUsedPct)))
            if (showStorage) add(Triple("DSK", diskUsedPct, usageColor(diskUsedPct)))
        }
        // 2026-06-06: slimmed to the only styles still in use after preset
        // cleanup. CLASICO uses GOLD_RINGS via SystemRingsRenderer (not us).
        // GROK/CRT/CYBER have showSystemHud=false so this draw() never runs
        // for them currently — kept here for future re-enable + the
        // GOLD_RINGS branch to remain a no-op if mis-routed.
        when (hudStyle) {
            HudStyle.HORIZONTAL_METERS -> drawHorizontalMeters(canvas, rows)
            HudStyle.HEX_LEDS -> drawHexLeds(canvas, rows)
            HudStyle.PILLAR_STACK -> drawPillarStack(canvas, rows)
            HudStyle.GOLD_RINGS -> { /* not drawn here — SystemRingsRenderer */ }
        }
    }

    // ── Vertical capacitor pillars — used by CRT Terminal preset. Three
    //    narrow vertical bars top-right; each fills from bottom proportional
    //    to its metric. Value label above, metric label below. Cyan glow.
    private fun drawPillarStack(canvas: Canvas, rows: List<Triple<String, Int, Int>>) {
        val pillarW = surfaceWidth * 0.026f       // ~28px on 1080
        val pillarH = surfaceHeight * 0.07f       // ~164px on 2340
        val gap = surfaceWidth * 0.015f
        val totalW = rows.size * pillarW + (rows.size - 1) * gap
        val rightMargin = surfaceWidth * 0.04f
        val startX = surfaceWidth - rightMargin - totalW
        val topY = surfaceHeight * 0.08f
        val valueSize = surfaceWidth * 0.022f
        val labelSize = surfaceWidth * 0.020f

        // Value paint (top of pillar)
        textPaint.apply {
            color = accentColor
            this.textSize = valueSize
            typeface = Typeface.create("sans-serif-condensed", Typeface.BOLD)
            textAlign = Paint.Align.CENTER
            letterSpacing = 0.04f
            shader = null
            setShadowLayer(4f, 0f, 0f, accentColor)
        }
        labelPaint.apply {
            color = Color.argb(180, Color.red(accentColor), Color.green(accentColor), Color.blue(accentColor))
            this.textSize = labelSize * 0.7f
            typeface = Typeface.MONOSPACE
            textAlign = Paint.Align.CENTER
            letterSpacing = 0.18f
            shader = null
            setShadowLayer(2f, 0f, 1f, Color.argb(120, 0, 0, 0))
        }

        for ((idx, row) in rows.withIndex()) {
            val (label, pct, color) = row
            val cx = startX + pillarW / 2 + idx * (pillarW + gap)
            val pillarLeft = cx - pillarW / 2
            val pillarRight = cx + pillarW / 2
            val pillarTop = topY
            val pillarBottom = topY + pillarH

            // Pillar shell — dark background + cyan border
            shapePaint.apply {
                this.color = Color.argb(180, 6, 18, 28)
                style = Paint.Style.FILL
                setShadowLayer(0f, 0f, 0f, 0)
            }
            canvas.drawRoundRect(pillarLeft, pillarTop, pillarRight, pillarBottom, 3f, 3f, shapePaint)
            strokePaint.apply {
                this.color = Color.argb(110, Color.red(accentColor), Color.green(accentColor), Color.blue(accentColor))
                strokeWidth = 1f
                style = Paint.Style.STROKE
            }
            canvas.drawRoundRect(pillarLeft, pillarTop, pillarRight, pillarBottom, 3f, 3f, strokePaint)

            // Fill from bottom — color tinted to the metric's status (color)
            val fillH = pillarH * (pct.coerceIn(0, 100) / 100f)
            shapePaint.apply {
                this.color = color
                alpha = 220
                style = Paint.Style.FILL
                setShadowLayer(6f, 0f, 0f, color)
            }
            canvas.drawRoundRect(
                pillarLeft + 2f, pillarBottom - fillH,
                pillarRight - 2f, pillarBottom - 2f,
                2f, 2f, shapePaint,
            )
            shapePaint.clearShadowLayer()

            // Value text ABOVE pillar
            canvas.drawText("$pct", cx, pillarTop - 6f, textPaint)
            // Label text BELOW pillar
            canvas.drawText(label, cx, pillarBottom + labelSize, labelPaint)
        }
    }

    // ── Top-right vertical pills: "84% ●" ───────────────────────────
    private fun drawMiniPills(canvas: Canvas, rows: List<Triple<String, Int, Int>>) {
        val textSize = surfaceWidth * 0.028f
        val right = surfaceWidth - surfaceWidth * 0.04f
        val top = surfaceHeight * 0.045f
        val rowGap = textSize * 1.7f
        val dotR = textSize * 0.32f
        val dotGap = textSize * 0.45f

        textPaint.apply {
            color = Color.argb(225, 255, 255, 255)
            this.textSize = textSize
            typeface = Typeface.MONOSPACE
            textAlign = Paint.Align.RIGHT
            letterSpacing = 0.05f
            shader = null
            setShadowLayer(4f, 0f, 1f, Color.argb(180, 0, 0, 0))
        }
        for ((idx, row) in rows.withIndex()) {
            val (_, pct, color) = row
            val y = top + idx * rowGap + textSize
            val textRight = right - dotR * 2 - dotGap
            canvas.drawText("$pct%", textRight, y, textPaint)
            dotPaint.apply {
                this.color = color
                style = Paint.Style.FILL
                setShadowLayer(dotR * 1.8f, 0f, 0f, color)
            }
            canvas.drawCircle(right - dotR, y - textSize * 0.32f, dotR, dotPaint)
        }
        dotPaint.setShadowLayer(0f, 0f, 0f, 0)
    }

    // ── Google-style pills with colored dot per metric (battery=green,
    //    ram=blue, disk=red) ─────────────────────────────────────────
    private fun drawPillsColored(canvas: Canvas, rows: List<Triple<String, Int, Int>>) {
        val googleColors = listOf(
            Color.parseColor("#34A853"),
            Color.parseColor("#4285F4"),
            Color.parseColor("#EA4335"),
        )
        val textSize = surfaceWidth * 0.027f
        val pillH = textSize * 1.9f
        val pillRadius = pillH / 2f
        val right = surfaceWidth - surfaceWidth * 0.04f
        val top = surfaceHeight * 0.04f
        val rowGap = pillH + 8f
        val dotR = textSize * 0.34f

        textPaint.apply {
            color = Color.argb(245, 255, 255, 255)
            this.textSize = textSize
            typeface = Typeface.DEFAULT
            textAlign = Paint.Align.RIGHT
            letterSpacing = 0.02f
            shader = null
            setShadowLayer(2f, 0f, 1f, Color.argb(140, 0, 0, 0))
        }
        for ((idx, row) in rows.withIndex()) {
            val (_, pct, _) = row
            val color = googleColors[idx % googleColors.size]
            val text = "$pct%"
            val textW = textPaint.measureText(text)
            val pillW = textW + dotR * 2 + 28f
            val cy = top + idx * rowGap + pillH / 2
            val left = right - pillW
            shapePaint.apply {
                this.color = Color.argb(60, 255, 255, 255)
                style = Paint.Style.FILL
                setShadowLayer(0f, 0f, 0f, 0)
            }
            canvas.drawRoundRect(left, cy - pillH/2, right, cy + pillH/2, pillRadius, pillRadius, shapePaint)
            strokePaint.apply {
                this.color = Color.argb(80, 255, 255, 255)
                strokeWidth = 1f
            }
            canvas.drawRoundRect(left, cy - pillH/2, right, cy + pillH/2, pillRadius, pillRadius, strokePaint)
            // Dot at left of pill
            dotPaint.apply { this.color = color; style = Paint.Style.FILL; setShadowLayer(0f, 0f, 0f, 0) }
            canvas.drawCircle(left + dotR + 8f, cy, dotR, dotPaint)
            canvas.drawText(text, right - 10f, cy + textSize * 0.36f, textPaint)
        }
    }

    // ── Bar-meter style — compact block on top-right matching mockup #75:
    //    LABEL | gradient bar | VALUE%   stacked vertically per metric.
    //    All three pieces sit adjacent on the right side; no longer split
    //    across the full screen width (previous version had label on far
    //    left + bar/value on far right, looked disconnected).
    private fun drawHorizontalMeters(canvas: Canvas, rows: List<Triple<String, Int, Int>>) {
        val textSize = surfaceWidth * 0.026f
        val right = surfaceWidth - surfaceWidth * 0.04f
        // top pushed down so HUD clears the Android status bar (where carrier
        // icons + system clock sit). Was 0.06 — overlapped on devices with a
        // tall status bar. 0.08 = ~64px on 2340-tall surface, safely below.
        val top = surfaceHeight * 0.08f
        val rowGap = textSize * 1.9f
        val barW = surfaceWidth * 0.13f
        val barH = textSize * 0.42f
        val labelW = textSize * 2.1f      // reserved width for "BAT/RAM/DSK"
        val gap = textSize * 0.4f         // gap between label/bar/value
        val valueW = textSize * 1.8f      // reserved width for "XX%"

        // Anchor: value column right-aligned at `right`. Bar to the left of it,
        // then label further left. Layout: [LABEL]  [====bar====]  [VAL%]
        val valueRightX = right
        val barRightX = valueRightX - valueW
        val barLeftX = barRightX - barW
        val labelLeftX = barLeftX - gap - labelW

        labelPaint.apply {
            color = Color.argb(210, 255, 255, 255)
            this.textSize = textSize * 0.78f
            typeface = Typeface.create("sans-serif-condensed", Typeface.BOLD)
            textAlign = Paint.Align.LEFT
            letterSpacing = 0.18f
            shader = null
            setShadowLayer(2f, 0f, 1f, Color.argb(140, 0, 0, 0))
        }
        textPaint.apply {
            color = Color.WHITE
            this.textSize = textSize * 0.88f
            typeface = Typeface.create("sans-serif-condensed", Typeface.BOLD)
            textAlign = Paint.Align.RIGHT
            letterSpacing = 0.04f
            setShadowLayer(3f, 0f, 1f, Color.argb(160, 0, 0, 0))
        }
        for ((idx, row) in rows.withIndex()) {
            val (label, pct, color) = row
            val cy = top + idx * rowGap
            val baseY = cy + textSize * 0.36f
            // LABEL — left
            canvas.drawText(label, labelLeftX, baseY, labelPaint)
            // BAR background (dim white)
            val barTop = baseY - barH * 1.1f
            shapePaint.apply {
                this.color = Color.argb(60, 255, 255, 255)
                style = Paint.Style.FILL
                setShadowLayer(0f, 0f, 0f, 0)
            }
            canvas.drawRoundRect(barLeftX, barTop, barRightX, barTop + barH, 2f, 2f, shapePaint)
            // BAR fill — gradient from the metric's accent color
            shapePaint.color = color
            canvas.drawRoundRect(
                barLeftX, barTop,
                barLeftX + barW * pct / 100f, barTop + barH,
                2f, 2f, shapePaint,
            )
            // VALUE — right
            canvas.drawText("$pct%", valueRightX, baseY, textPaint)
        }
    }

    // ── Hexagonal LED cells with value inside ───────────────────────
    private fun drawHexLeds(canvas: Canvas, rows: List<Triple<String, Int, Int>>) {
        val cellW = surfaceWidth * 0.13f
        val cellH = cellW * 1.1f
        val gap = surfaceWidth * 0.02f
        val totalW = rows.size * cellW + (rows.size - 1) * gap
        val startX = (surfaceWidth - totalW) / 2
        val top = surfaceHeight * 0.045f

        for ((idx, row) in rows.withIndex()) {
            val (label, pct, color) = row
            val cx = startX + idx * (cellW + gap) + cellW / 2
            val cy = top + cellH / 2
            buildHexPath(cx, cy, cellW / 2, cellH / 2)
            shapePaint.apply {
                this.color = Color.argb(40, Color.red(color), Color.green(color), Color.blue(color))
                style = Paint.Style.FILL
                setShadowLayer(0f, 0f, 0f, 0)
            }
            canvas.drawPath(hexPath, shapePaint)
            strokePaint.apply { this.color = color; strokeWidth = 1.5f }
            canvas.drawPath(hexPath, strokePaint)
            textPaint.apply {
                this.color = color
                this.textSize = cellH * 0.30f
                typeface = Typeface.create("sans-serif-condensed", Typeface.BOLD)
                textAlign = Paint.Align.CENTER
                letterSpacing = 0.06f
                setShadowLayer(4f, 0f, 0f, color)
            }
            canvas.drawText("$pct", cx, cy + cellH * 0.05f, textPaint)
            labelPaint.apply {
                this.color = Color.argb(180, Color.red(color), Color.green(color), Color.blue(color))
                this.textSize = cellH * 0.16f
                typeface = Typeface.MONOSPACE
                textAlign = Paint.Align.CENTER
                letterSpacing = 0.16f
                setShadowLayer(0f, 0f, 0f, 0)
            }
            canvas.drawText(label, cx, cy + cellH * 0.32f, labelPaint)
        }
    }

    // ── Terminal lines: "RAM [████████░░] 67%" ─────────────────────
    private fun drawAsciiLines(canvas: Canvas, rows: List<Triple<String, Int, Int>>) {
        val textSize = surfaceWidth * 0.034f
        val right = surfaceWidth - surfaceWidth * 0.04f
        val top = surfaceHeight * 0.05f
        val rowGap = textSize * 1.45f
        textPaint.apply {
            color = accentColor
            this.textSize = textSize
            typeface = Typeface.MONOSPACE
            textAlign = Paint.Align.RIGHT
            letterSpacing = 0.02f
            setShadowLayer(6f, 0f, 0f, accentColor)
        }
        for ((idx, row) in rows.withIndex()) {
            val (label, pct, _) = row
            val cy = top + idx * rowGap + textSize
            val filled = (pct / 10).coerceIn(0, 10)
            val bar = "█".repeat(filled) + "░".repeat(10 - filled)
            canvas.drawText("$label [$bar] ${"%3d".format(pct)}%", right, cy, textPaint)
        }
        textPaint.setShadowLayer(0f, 0f, 0f, 0)
    }

    // ── Mini arc gauges with percentage in center ──────────────────
    private fun drawArcGauges(canvas: Canvas, rows: List<Triple<String, Int, Int>>) {
        val r = surfaceWidth * 0.07f
        val gap = surfaceWidth * 0.03f
        val totalW = rows.size * (r * 2) + (rows.size - 1) * gap
        val startX = (surfaceWidth - totalW) / 2
        val top = surfaceHeight * 0.045f + r

        for ((idx, row) in rows.withIndex()) {
            val (label, pct, color) = row
            val cx = startX + idx * (r * 2 + gap) + r
            val arc = RectF(cx - r, top - r, cx + r, top + r)
            strokePaint.apply {
                this.color = Color.argb(60, 255, 255, 255)
                strokeWidth = 2.5f
                strokeCap = Paint.Cap.ROUND
            }
            canvas.drawArc(arc, -90f, 360f, false, strokePaint)
            strokePaint.color = color
            strokePaint.setShadowLayer(8f, 0f, 0f, color)
            canvas.drawArc(arc, -90f, 360f * pct / 100f, false, strokePaint)
            strokePaint.setShadowLayer(0f, 0f, 0f, 0)
            textPaint.apply {
                this.color = Color.WHITE
                this.textSize = r * 0.55f
                typeface = Typeface.DEFAULT
                textAlign = Paint.Align.CENTER
                letterSpacing = 0f
                setShadowLayer(3f, 0f, 1f, Color.BLACK)
            }
            canvas.drawText("$pct", cx, top + r * 0.18f, textPaint)
            labelPaint.apply {
                this.color = Color.argb(200, 255, 255, 255)
                this.textSize = r * 0.30f
                typeface = Typeface.MONOSPACE
                textAlign = Paint.Align.CENTER
                letterSpacing = 0.16f
                setShadowLayer(2f, 0f, 1f, Color.BLACK)
            }
            canvas.drawText(label, cx, top + r * 1.55f, labelPaint)
        }
    }

    // ── Glass shards (light theme) ─────────────────────────────────
    private fun drawGlassShards(canvas: Canvas, rows: List<Triple<String, Int, Int>>) {
        val shardW = surfaceWidth * 0.14f
        val shardH = shardW * 1.05f
        val gap = surfaceWidth * 0.02f
        val totalW = rows.size * shardW + (rows.size - 1) * gap
        val startX = (surfaceWidth - totalW) / 2
        val top = surfaceHeight * 0.045f

        for ((idx, row) in rows.withIndex()) {
            val (label, pct, _) = row
            val left = startX + idx * (shardW + gap)
            // trapezoid: 15% inset top, 100% bottom
            shardPath.reset()
            shardPath.moveTo(left + shardW * 0.15f, top)
            shardPath.lineTo(left + shardW * 0.85f, top)
            shardPath.lineTo(left + shardW, top + shardH)
            shardPath.lineTo(left, top + shardH)
            shardPath.close()
            shapePaint.apply {
                style = Paint.Style.FILL
                shader = LinearGradient(left, top, left + shardW, top + shardH,
                    Color.argb(220, 255, 255, 255), Color.argb(170, 220, 230, 250),
                    Shader.TileMode.CLAMP)
                setShadowLayer(0f, 0f, 0f, 0)
            }
            canvas.drawPath(shardPath, shapePaint)
            shapePaint.shader = null
            strokePaint.apply { this.color = Color.argb(220, 255, 255, 255); strokeWidth = 1f }
            canvas.drawPath(shardPath, strokePaint)
            textPaint.apply {
                this.color = Color.parseColor("#2A3548")
                this.textSize = shardH * 0.26f
                typeface = Typeface.SERIF
                textAlign = Paint.Align.CENTER
                letterSpacing = 0.02f
                setShadowLayer(0f, 0f, 0f, 0)
            }
            canvas.drawText("$pct%", left + shardW / 2, top + shardH * 0.55f, textPaint)
            labelPaint.apply {
                this.color = Color.parseColor("#5A6878")
                this.textSize = shardH * 0.14f
                typeface = Typeface.MONOSPACE
                textAlign = Paint.Align.CENTER
                letterSpacing = 0.16f
            }
            canvas.drawText(label, left + shardW / 2, top + shardH * 0.85f, labelPaint)
        }
    }

    private fun buildHexPath(cx: Float, cy: Float, rx: Float, ry: Float) {
        hexPath.reset()
        for (i in 0 until 6) {
            val a = (Math.PI / 3 * i - Math.PI / 2).toFloat()
            val x = cx + Math.cos(a.toDouble()).toFloat() * rx
            val y = cy + Math.sin(a.toDouble()).toFloat() * ry
            if (i == 0) hexPath.moveTo(x, y) else hexPath.lineTo(x, y)
        }
        hexPath.close()
    }

    private fun batteryColor(pct: Int): Int = when {
        pct <= 15 -> Color.rgb(0xFF, 0x15, 0x00)
        pct <= 30 -> Color.rgb(0xFF, 0xFF, 0x00)
        else -> accentColor
    }

    private fun usageColor(pct: Int): Int = when {
        pct >= 90 -> Color.rgb(0xFF, 0x15, 0x00)
        pct >= 75 -> Color.rgb(0xFF, 0xFF, 0x00)
        else -> accentColor
    }
}
