package com.orbix.pixora.scene

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Camera
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.Typeface
import org.json.JSONObject

/**
 * Pixora "P" branding logo rendered in 3D via [android.graphics.Camera].
 *
 * Spins around the Y axis like the RARE logo intro on N64 — gold metallic
 * gradient + soft glow + bevel highlight. Drawn LAST in CanvasSceneRenderer
 * so it sits on top of everything.
 *
 * Per-scene control via spec.branding:
 *   "branding": {
 *     "enabled": true,                 // default true
 *     "x": 0.92, "y": 0.945,           // normalized position (default bottom-right)
 *     "size": 0.07,                    // size as fraction of surfaceWidth
 *     "rotation_speed": 0.020          // radians/frame (default ~one rev per 5s @ 60fps)
 *   }
 * Or simply { "enabled": false } to hide it.
 */
class BrandingLogo(private val context: Context) {

    var enabled: Boolean = true
    var positionX: Float = 0.92f
    var positionY: Float = 0.945f
    var sizeFrac: Float = 0.07f
    var rotationSpeed: Float = 0.020f

    private var logoBitmap: Bitmap? = null
    private var logoSize: Int = 0
    private val camera = Camera()
    private val matrix = Matrix()
    private val drawPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    /** Reset to factory defaults (called before applying any per-scene override). */
    fun resetDefaults() {
        enabled = true
        positionX = 0.92f
        positionY = 0.945f
        sizeFrac = 0.07f
        rotationSpeed = 0.020f
    }

    /** Reset to defaults, then apply spec overrides. Pass null to just reset. */
    fun loadFrom(spec: JSONObject?) {
        resetDefaults()
        spec ?: return
        enabled = spec.optBoolean("enabled", enabled)
        positionX = spec.optDouble("x", positionX.toDouble()).toFloat()
        positionY = spec.optDouble("y", positionY.toDouble()).toFloat()
        sizeFrac = spec.optDouble("size", sizeFrac.toDouble()).toFloat()
        rotationSpeed = spec.optDouble("rotation_speed", rotationSpeed.toDouble()).toFloat()
    }

    fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        if (!enabled || surfaceW <= 0) return
        val targetSize = (surfaceW * sizeFrac).toInt().coerceAtLeast(48)
        if (logoBitmap == null || logoSize != targetSize) {
            logoBitmap?.recycle()
            logoBitmap = createPLogo(targetSize)
            logoSize = targetSize
        }
        val bmp = logoBitmap ?: return

        // Y-axis rotation in degrees, slow constant spin.
        val angleDeg = (tick * rotationSpeed * 180f / Math.PI).toFloat() % 360f

        camera.save()
        camera.rotateY(angleDeg)
        camera.getMatrix(matrix)
        camera.restore()

        // Center rotation around the bitmap center, then position on screen.
        val cx = surfaceW * positionX
        val cy = surfaceH * positionY
        matrix.preTranslate(-bmp.width / 2f, -bmp.height / 2f)
        matrix.postTranslate(cx, cy)

        canvas.drawBitmap(bmp, matrix, drawPaint)
    }

    fun release() {
        logoBitmap?.recycle()
        logoBitmap = null
        logoSize = 0
    }

    /** Build the gold "P" once for a given target size. */
    private fun createPLogo(size: Int): Bitmap {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val pad = size * 0.10f

        // Soft outer glow (drawn first so the letter sits on top)
        val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x66F0DD9E.toInt()
            maskFilter = BlurMaskFilter(size * 0.10f, BlurMaskFilter.Blur.NORMAL)
            typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
            textSize = size * 0.92f
            textAlign = Paint.Align.CENTER
        }
        val baselineGlow = baselineFor(glowPaint, size)
        c.drawText("P", size / 2f, baselineGlow, glowPaint)

        // Main gold gradient body
        val mainPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f, pad, 0f, size - pad,
                intArrayOf(
                    0xFFF0DD9E.toInt(),  // top: bright gold
                    0xFFC9A650.toInt(),  // mid: pixora gold
                    0xFF8A6F33.toInt(),  // bottom: deep gold
                ),
                floatArrayOf(0f, 0.5f, 1f),
                Shader.TileMode.CLAMP,
            )
            typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
            textSize = size * 0.92f
            textAlign = Paint.Align.CENTER
        }
        val baseline = baselineFor(mainPaint, size)
        c.drawText("P", size / 2f, baseline, mainPaint)

        // Top-left specular highlight (a thin bright stroke on the left edge of the P)
        val highlightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f, 0f, 0f, size.toFloat(),
                intArrayOf(0x80FFFFFF.toInt(), 0x00FFFFFF),
                floatArrayOf(0f, 0.45f),
                Shader.TileMode.CLAMP,
            )
            style = Paint.Style.STROKE
            strokeWidth = size * 0.018f
            typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
            textSize = size * 0.92f
            textAlign = Paint.Align.CENTER
        }
        c.drawText("P", size / 2f, baseline, highlightPaint)

        return bmp
    }

    private fun baselineFor(p: Paint, size: Int): Float {
        val m = p.fontMetrics
        return size / 2f - (m.ascent + m.descent) / 2f
    }
}
