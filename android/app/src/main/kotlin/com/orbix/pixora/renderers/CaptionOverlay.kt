package com.orbix.pixora.renderers

import android.graphics.*
import android.text.TextPaint

class CaptionOverlay {

    var currentCaption: String? = null
    private var captionAlpha = 0f
    var lastCaptionChange = 0L
    var lastCaptionShowTime = 0L
    private val captionShowDurationMs = 30_000L
    private val captionIntervalMs = 180_000L
    private val captionFadeInMs = 600f
    private val captionFadeOutMs = 800f

    private val captionTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val captionBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    // Pre-allocated RectF for draw loop reuse
    private val outerGlowRect = RectF()
    private val bgRect = RectF()
    private val accentRect = RectF()

    // Cached BlurMaskFilter (recreated only when surfaceWidth changes)
    private var cachedBlurFilter: BlurMaskFilter? = null
    private var cachedBlurWidth = 0

    // Cached word-wrap results (recalculated only when caption or width changes)
    private data class CaptionWord(val text: String, val highlight: Boolean)
    private data class LineWord(val text: String, val highlight: Boolean)
    private var cachedCaption: String? = null
    private var cachedMaxWidth = 0f
    private var cachedTextSize = 0f
    private var cachedLines: List<List<LineWord>> = emptyList()

    // Character names to highlight in glow color
    private val highlightWords = setOf(
        "GOKU", "VEGETA", "GOHAN", "GOTEN", "TRUNKS", "PICCOLO",
        "FRIEZA", "FREEZER", "CELL", "BUU", "BILLS", "BEERUS",
        "WHIS", "KRILLIN", "BULMA", "CHICHI", "MR. SATAN", "SATAN",
        "MAJIN BUU", "MAJIN", "GENKI DAMA", "SPIRIT BOMB",
        "SUPER SAIYAN", "GOD", "KAIO", "KAIOUSAMA",
        "CHOU GENKI DAMA", "SAIYAN"
    )

    var surfaceWidth = 0
    var surfaceHeight = 0
    var glowColor = Color.parseColor("#C9A650")

    fun draw(canvas: Canvas) {
        val text = currentCaption ?: return
        if (text.isEmpty() || surfaceWidth <= 0) return

        val now = System.currentTimeMillis()
        val timeSinceShow = now - lastCaptionShowTime

        // Cycle: visible for 30s, then hidden until 3 min mark
        if (timeSinceShow > captionShowDurationMs) {
            if (timeSinceShow >= captionIntervalMs) {
                lastCaptionShowTime = now
            }
            return
        }

        // Fade in over 600ms, fade out over last 800ms of the 30s window
        val timeLeft = captionShowDurationMs - timeSinceShow
        captionAlpha = if (timeSinceShow < captionFadeInMs) {
            timeSinceShow / captionFadeInMs
        } else if (timeLeft < captionFadeOutMs) {
            timeLeft / captionFadeOutMs
        } else {
            1f
        }
        val alpha = (captionAlpha * 240).toInt()
        if (alpha <= 0) return

        val w = surfaceWidth.toFloat()
        val h = surfaceHeight.toFloat()
        val margin = w * 0.05f
        val maxWidth = w - margin * 2 - w * 0.025f

        val textSize = w * 0.034f

        // Recalculate word-wrap only when caption or layout changes
        if (text != cachedCaption || maxWidth != cachedMaxWidth || textSize != cachedTextSize) {
            cachedCaption = text
            cachedMaxWidth = maxWidth
            cachedTextSize = textSize

            val rawWords = text.split(" ")
            val captionWords = mutableListOf<CaptionWord>()

            var i = 0
            while (i < rawWords.size) {
                var matched = false
                if (i + 1 < rawWords.size) {
                    val twoWord = "${rawWords[i]} ${rawWords[i+1]}"
                    if (highlightWords.contains(twoWord.uppercase())) {
                        captionWords.add(CaptionWord(twoWord, true))
                        i += 2
                        matched = true
                    }
                }
                if (!matched) {
                    val isHighlight = highlightWords.contains(rawWords[i].uppercase().trimEnd(',', '.', '!', '?'))
                    captionWords.add(CaptionWord(rawWords[i], isHighlight))
                    i++
                }
            }

            // Measure and word-wrap
            captionTextPaint.textSize = textSize
            captionTextPaint.typeface = Typeface.DEFAULT

            val lines = mutableListOf<MutableList<LineWord>>()
            var currentLine = mutableListOf<LineWord>()
            var currentWidth = 0f

            for (word in captionWords) {
                captionTextPaint.typeface = if (word.highlight)
                    Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                val wordWidth = captionTextPaint.measureText(word.text + " ")
                if (currentWidth + wordWidth > maxWidth && currentLine.isNotEmpty()) {
                    lines.add(currentLine)
                    currentLine = mutableListOf()
                    currentWidth = 0f
                }
                currentLine.add(LineWord(word.text, word.highlight))
                currentWidth += wordWidth
            }
            if (currentLine.isNotEmpty()) lines.add(currentLine)
            cachedLines = lines
        }

        val lines = cachedLines

        val lineHeight = textSize * 1.5f
        val totalTextHeight = lines.size * lineHeight
        val padding = w * 0.03f
        val accentWidth = w * 0.008f

        // Background box
        val boxBottom = h * 0.80f
        val boxTop = boxBottom - totalTextHeight - padding * 2
        val boxLeft = margin - padding
        val boxRight = w - margin + padding

        // Outer glow (cache BlurMaskFilter when width changes)
        if (cachedBlurWidth != surfaceWidth) {
            cachedBlurWidth = surfaceWidth
            cachedBlurFilter = BlurMaskFilter(w * 0.02f, BlurMaskFilter.Blur.OUTER)
        }
        captionBgPaint.color = glowColor
        captionBgPaint.alpha = (alpha * 0.15f).toInt()
        captionBgPaint.maskFilter = cachedBlurFilter
        outerGlowRect.set(boxLeft - 4, boxTop - 4, boxRight + 4, boxBottom + 4)
        canvas.drawRoundRect(
            outerGlowRect,
            w * 0.025f, w * 0.025f, captionBgPaint
        )
        captionBgPaint.maskFilter = null

        // Background
        captionBgPaint.color = Color.BLACK
        captionBgPaint.alpha = (alpha * 0.70f).toInt()
        bgRect.set(boxLeft, boxTop, boxRight, boxBottom)
        canvas.drawRoundRect(
            bgRect,
            w * 0.02f, w * 0.02f, captionBgPaint
        )

        // Accent bar on left (glow colored)
        captionBgPaint.color = glowColor
        captionBgPaint.alpha = (alpha * 0.9f).toInt()
        accentRect.set(boxLeft + padding * 0.3f, boxTop + padding * 0.6f,
            boxLeft + padding * 0.3f + accentWidth, boxBottom - padding * 0.6f)
        canvas.drawRoundRect(
            accentRect,
            accentWidth / 2, accentWidth / 2, captionBgPaint
        )

        // Draw text word by word with highlights
        val textLeft = margin + accentWidth + padding * 0.3f
        var y = boxTop + padding + textSize * 1.1f

        for (line in lines) {
            var x = textLeft
            for (word in line) {
                if (word.highlight) {
                    captionTextPaint.color = glowColor
                    captionTextPaint.typeface = Typeface.DEFAULT_BOLD
                    captionTextPaint.alpha = alpha
                    captionTextPaint.setShadowLayer(6f, 0f, 0f, glowColor)
                } else {
                    captionTextPaint.color = Color.WHITE
                    captionTextPaint.typeface = Typeface.DEFAULT
                    captionTextPaint.alpha = (alpha * 0.92f).toInt()
                    captionTextPaint.setShadowLayer(3f, 0f, 2f, Color.BLACK)
                }
                captionTextPaint.textAlign = Paint.Align.LEFT
                canvas.drawText(word.text, x, y, captionTextPaint)
                x += captionTextPaint.measureText(word.text + " ")
            }
            y += lineHeight
        }
    }
}
