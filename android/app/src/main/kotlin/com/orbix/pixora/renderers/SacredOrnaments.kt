package com.orbix.pixora.renderers

import android.graphics.*

/**
 * SACRED v2 (2026-06-05) — 4 corner ornaments rendered when the SACRED
 * preset is active. Each corner is a small sacred-geometry glyph: an
 * L-bracket framing + center dot + cross-tick crosshair. Subtle (alpha
 * ~140 of glow color) so it never competes with the clock or content.
 *
 * Only drawn when preset == SACRED; other presets get no ornaments to
 * keep their personalities distinct.
 */
class SacredOrnaments {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f
        strokeCap = Paint.Cap.ROUND
        color = Color.parseColor("#E6B655")
        alpha = 140
    }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 0.8f
        color = Color.parseColor("#E6B655")
        alpha = 120
    }

    var surfaceWidth = 0
    var surfaceHeight = 0
    var accentColor: Int = Color.parseColor("#E6B655")
        set(value) {
            field = value
            paint.color = value
            dotPaint.color = value
        }

    fun draw(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        val size = surfaceWidth * 0.06f
        val margin = surfaceWidth * 0.035f
        // Push the bottom ornaments above the dock area (~64dp).
        val bottomMargin = surfaceHeight * 0.13f

        // Top-left
        drawOrnament(canvas, margin, margin + surfaceHeight * 0.02f, size, +1, +1)
        // Top-right
        drawOrnament(canvas, surfaceWidth - margin, margin + surfaceHeight * 0.02f, size, -1, +1)
        // Bottom-left
        drawOrnament(canvas, margin, surfaceHeight - bottomMargin, size, +1, -1)
        // Bottom-right
        drawOrnament(canvas, surfaceWidth - margin, surfaceHeight - bottomMargin, size, -1, -1)
    }

    /** Each corner is a small open L + center circle + tiny cross marks.
     *  signX/signY = ±1 picks which corner direction the L brackets open. */
    private fun drawOrnament(canvas: Canvas, x: Float, y: Float, size: Float, signX: Int, signY: Int) {
        val dx = size * signX
        val dy = size * signY

        // L bracket from corner — two short arms
        paint.alpha = 130
        canvas.drawLine(x, y, x + dx * 0.4f, y, paint)
        canvas.drawLine(x, y, x, y + dy * 0.4f, paint)

        // Inner circle at the bracket apex
        dotPaint.alpha = 110
        canvas.drawCircle(x + dx * 0.5f, y + dy * 0.5f, size * 0.12f, dotPaint)

        // Crosshair through the inner circle
        paint.alpha = 90
        canvas.drawLine(
            x + dx * 0.5f, y + dy * 0.3f,
            x + dx * 0.5f, y + dy * 0.7f, paint
        )
        canvas.drawLine(
            x + dx * 0.3f, y + dy * 0.5f,
            x + dx * 0.7f, y + dy * 0.5f, paint
        )
    }
}
