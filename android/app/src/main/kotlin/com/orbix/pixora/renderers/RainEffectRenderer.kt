package com.orbix.pixora.renderers

import android.graphics.*
import com.orbix.pixora.PixoraWallpaperService
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

data class RainDrop(
    var x: Float, var y: Float,
    val speed: Float, val length: Float,
    val alpha: Int, val windOffset: Float
)

data class GlassDrop(
    var x: Float, var y: Float,
    val radius: Float, val slideSpeed: Float,
    val trailLength: Float, val alpha: Int
)

data class CityLight(
    val x: Float, val y: Float,
    val baseAlpha: Int, val flickerSpeed: Float,
    val flickerOffset: Float, val radius: Float,
    val color: Int
)

class RainEffectRenderer {

    private val rainDrops = mutableListOf<RainDrop>()
    private val glassDrops = mutableListOf<GlassDrop>()
    private val cityLights = mutableListOf<CityLight>()

    private val rainPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val glassPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val cityPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val overlayPaint = Paint()
    private val lampPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val headphonePaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private var rainInitialized = false

    // Pre-allocated arrays for RadialGradient construction (city lights)
    private val cityGradientColors = IntArray(3)
    private val cityGradientStops = floatArrayOf(0f, 0.3f, 1f)

    // Pre-allocated arrays for lamp glow gradients
    private val lampGradientColors3 = IntArray(3)
    private val lampGradientStops3 = floatArrayOf(0f, 0.5f, 1f)
    private val lampGradientColors4 = IntArray(4)
    private val lampGradientStops4 = floatArrayOf(0f, 0.15f, 0.45f, 1f)

    // Pre-allocated arrays for headphone glow gradients
    private val hpGradientColors = IntArray(3)
    private val hpGradientStops = floatArrayOf(0f, 0.4f, 1f)

    // Window region in normalized coords (0..1) based on the lofi_girl_rain image
    private val winLeft = 0.0f
    private val winRight = 0.47f
    private val winTop = 0.0f
    private val winBottom = 0.53f

    var surfaceWidth = 0
    var surfaceHeight = 0
    var glowColor = Color.parseColor("#7C4DFF")
    var animationPhase = 0f
    var isRainWallpaper = false
    var hasAudio = false
    var smoothLevels: FloatArray = FloatArray(PixoraWallpaperService.BAR_COUNT)

    private fun initRain() {
        if (rainInitialized || surfaceWidth <= 0 || surfaceHeight <= 0) return
        rainInitialized = true

        val wL = winLeft * surfaceWidth
        val wR = winRight * surfaceWidth
        val wT = winTop * surfaceHeight
        val wB = winBottom * surfaceHeight
        val regionW = wR - wL
        val regionH = wB - wT

        // Falling rain streaks -- only inside window
        for (i in 0 until PixoraWallpaperService.RAIN_DROP_COUNT) {
            rainDrops.add(RainDrop(
                x = wL + Random.nextFloat() * regionW,
                y = wT + Random.nextFloat() * regionH,
                speed = 8f + Random.nextFloat() * 14f,
                length = 15f + Random.nextFloat() * 30f,
                alpha = 30 + Random.nextInt(55),
                windOffset = Random.nextFloat() * 1.5f - 0.3f
            ))
        }

        // Glass drops on window surface
        for (i in 0 until PixoraWallpaperService.GLASS_DROP_COUNT) {
            glassDrops.add(GlassDrop(
                x = wL + Random.nextFloat() * regionW,
                y = wT + Random.nextFloat() * regionH,
                radius = 2f + Random.nextFloat() * 3.5f,
                slideSpeed = 0.3f + Random.nextFloat() * 1.0f,
                trailLength = 25f + Random.nextFloat() * 60f,
                alpha = 20 + Random.nextInt(40)
            ))
        }

        // City lights
        val cityColors = intArrayOf(
            Color.rgb(255, 220, 120),
            Color.rgb(255, 180, 100),
            Color.rgb(255, 150, 200),
            Color.rgb(180, 160, 255),
            Color.rgb(120, 200, 255),
            Color.rgb(255, 255, 200),
        )
        val cityRight = 0.36f
        for (i in 0 until PixoraWallpaperService.CITY_LIGHT_COUNT) {
            val cx = (winLeft + 0.02f + Random.nextFloat() * (cityRight - winLeft - 0.04f)) * surfaceWidth
            val cy = (winTop + 0.05f + Random.nextFloat() * (winBottom - winTop - 0.10f)) * surfaceHeight
            cityLights.add(CityLight(
                x = cx, y = cy,
                baseAlpha = 80 + Random.nextInt(100),
                flickerSpeed = 0.5f + Random.nextFloat() * 3f,
                flickerOffset = Random.nextFloat() * 6.28f,
                radius = 3f + Random.nextFloat() * 5f,
                color = cityColors[Random.nextInt(cityColors.size)]
            ))
        }
    }

    fun draw(canvas: Canvas) {
        if (!isRainWallpaper) return
        if (surfaceWidth <= 0 || surfaceHeight <= 0) return
        if (!rainInitialized) initRain()

        val w = surfaceWidth.toFloat()
        val h = surfaceHeight.toFloat()

        // Window bounds in pixels
        val wL = winLeft * w
        val wR = winRight * w
        val wT = winTop * h
        val wB = winBottom * h
        val regionW = wR - wL

        // Clip all rain drawing to the window region
        canvas.save()
        canvas.clipRect(wL, wT, wR, wB)

        // 1) Slight blue-dark overlay on window only (rainy atmosphere)
        overlayPaint.color = Color.argb(12, 0, 10, 30)
        canvas.drawRect(wL, wT, wR, wB, overlayPaint)

        // 2) Falling rain streaks (diagonal, fast) -- window only
        rainPaint.strokeCap = Paint.Cap.ROUND
        for (drop in rainDrops) {
            drop.y += drop.speed
            drop.x += drop.windOffset + 1.2f

            if (drop.y > wB + drop.length) {
                drop.y = wT - drop.length
                drop.x = wL + Random.nextFloat() * regionW
            }
            if (drop.x > wR + 10f) {
                drop.x = wL - 5f
            }

            rainPaint.color = Color.argb(drop.alpha, 180, 200, 220)
            rainPaint.strokeWidth = 1.2f

            val endX = drop.x + drop.length * 0.1f
            val endY = drop.y + drop.length
            canvas.drawLine(drop.x, drop.y, endX, endY, rainPaint)
        }

        // 3) Glass drops (slow round drops sliding down window)
        for (drop in glassDrops) {
            drop.y += drop.slideSpeed
            drop.x += sin((animationPhase * 0.5f + drop.x * 0.01f).toDouble()).toFloat() * 0.25f

            if (drop.y > wB + drop.trailLength) {
                drop.y = wT - drop.trailLength
                drop.x = wL + Random.nextFloat() * regionW
            }

            // Trail line
            glassPaint.color = Color.argb(drop.alpha / 2, 160, 190, 210)
            glassPaint.strokeWidth = drop.radius * 0.5f
            glassPaint.strokeCap = Paint.Cap.ROUND
            glassPaint.style = Paint.Style.STROKE
            canvas.drawLine(
                drop.x, drop.y - drop.trailLength,
                drop.x, drop.y,
                glassPaint
            )

            // Drop circle
            glassPaint.style = Paint.Style.FILL
            glassPaint.color = Color.argb(drop.alpha, 200, 215, 230)
            canvas.drawCircle(drop.x, drop.y, drop.radius, glassPaint)

            // Bright highlight
            glassPaint.color = Color.argb(drop.alpha + 15, 240, 245, 255)
            canvas.drawCircle(
                drop.x - drop.radius * 0.3f,
                drop.y - drop.radius * 0.3f,
                drop.radius * 0.3f,
                glassPaint
            )
        }

        // 4) City lights flickering in the buildings -- RadialGradient bloom
        for (light in cityLights) {
            val flicker = sin((animationPhase * light.flickerSpeed + light.flickerOffset).toDouble()).toFloat()
            val alpha = (light.baseAlpha + flicker * 60).toInt().coerceIn(20, 255)
            val bloomRadius = light.radius * 5f

            val lr = Color.red(light.color)
            val lg = Color.green(light.color)
            val lb = Color.blue(light.color)

            cityGradientColors[0] = Color.argb(alpha, lr, lg, lb)
            cityGradientColors[1] = Color.argb((alpha * 0.4f).toInt(), lr, lg, lb)
            cityGradientColors[2] = Color.argb(0, lr, lg, lb)
            cityPaint.shader = RadialGradient(
                light.x, light.y, bloomRadius,
                cityGradientColors,
                cityGradientStops,
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(light.x, light.y, bloomRadius, cityPaint)
            cityPaint.shader = null

            // Bright center dot
            cityPaint.color = Color.argb(min(255, alpha + 60), lr, lg, lb)
            canvas.drawCircle(light.x, light.y, light.radius, cityPaint)
        }

        // 5) Occasional lightning flash (only on window area)
        val flashChance = (animationPhase * 30f).toInt() % 600
        if (flashChance == 0) {
            overlayPaint.color = Color.argb(18, 200, 210, 255)
            canvas.drawRect(wL, wT, wR, wB, overlayPaint)
        }

        canvas.restore()

        // Effects outside window (no clip)
        drawLampGlow(canvas)
    }

    private fun drawLampGlow(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0 || !isRainWallpaper) return
        val w = surfaceWidth.toFloat()
        val h = surfaceHeight.toFloat()

        // Lamp bulb center
        val lampX = 0.06f * w
        val lampY = 0.41f * h
        // Book/desk center
        val bookX = 0.30f * w
        val bookY = 0.68f * h

        val pulse = sin((animationPhase * 0.5).toDouble()).toFloat() * 0.08f + 0.92f

        // 1) Bright bulb point
        val bulbRadius = w * 0.045f
        lampGradientColors3[0] = Color.argb(255, 255, 250, 230)
        lampGradientColors3[1] = Color.argb(220, 255, 230, 160)
        lampGradientColors3[2] = Color.argb(0, 255, 200, 100)
        lampPaint.shader = RadialGradient(
            lampX, lampY, bulbRadius,
            lampGradientColors3,
            lampGradientStops3,
            Shader.TileMode.CLAMP
        )
        canvas.drawCircle(lampX, lampY, bulbRadius, lampPaint)

        // 2) Light cone toward the book
        val coneRadius = w * 0.40f * pulse

        lampGradientColors4[0] = Color.argb((230 * pulse).toInt(), 255, 220, 140)
        lampGradientColors4[1] = Color.argb((150 * pulse).toInt(), 255, 200, 100)
        lampGradientColors4[2] = Color.argb((60 * pulse).toInt(), 255, 175, 70)
        lampGradientColors4[3] = Color.argb(0, 255, 150, 40)
        lampPaint.shader = RadialGradient(
            lampX, lampY, coneRadius,
            lampGradientColors4,
            lampGradientStops4,
            Shader.TileMode.CLAMP
        )
        canvas.save()
        canvas.translate(lampX, lampY)
        canvas.scale(1f, 1.8f)
        canvas.translate(-lampX, -lampY)
        canvas.drawCircle(lampX, lampY, coneRadius, lampPaint)
        canvas.restore()

        // 3) Warm glow on the book/desk area
        val bookGlow = w * 0.22f
        lampGradientColors3[0] = Color.argb((120 * pulse).toInt(), 255, 215, 140)
        lampGradientColors3[1] = Color.argb((55 * pulse).toInt(), 255, 195, 100)
        lampGradientColors3[2] = Color.argb(0, 255, 170, 60)
        lampPaint.shader = RadialGradient(
            bookX, bookY, bookGlow,
            lampGradientColors3,
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP
        )
        canvas.drawCircle(bookX, bookY, bookGlow, lampPaint)
        lampPaint.shader = null
    }

    fun drawHeadphoneGlow(canvas: Canvas) {
        if (surfaceWidth <= 0 || surfaceHeight <= 0 || !isRainWallpaper) return

        val w = surfaceWidth.toFloat()
        val h = surfaceHeight.toFloat()

        // Headphones center
        val hpX = 0.62f * w
        val hpY = 0.30f * h

        val gr = Color.red(glowColor)
        val gg = Color.green(glowColor)
        val gb = Color.blue(glowColor)

        // Always show a subtle breathing glow on headphones
        val breathe = sin((animationPhase * 0.7).toDouble()).toFloat() * 0.3f + 0.7f
        val idleRadius = w * 0.09f * breathe
        val idleAlpha = (60 * breathe).toInt()

        hpGradientColors[0] = Color.argb(idleAlpha, gr, gg, gb)
        hpGradientColors[1] = Color.argb((idleAlpha * 0.3f).toInt(), gr, gg, gb)
        hpGradientColors[2] = Color.argb(0, gr, gg, gb)
        headphonePaint.shader = RadialGradient(
            hpX, hpY, idleRadius,
            hpGradientColors,
            hpGradientStops,
            Shader.TileMode.CLAMP
        )
        canvas.drawCircle(hpX, hpY, idleRadius, headphonePaint)
        headphonePaint.shader = null

        // When music plays, add reactive pulse on top
        if (hasAudio) {
            val avgLevel = smoothLevels.average().toFloat()
            val intensity = (avgLevel * 3f).coerceIn(0f, 1f)
            if (intensity > 0.02f) {
                val beatRadius = w * 0.12f + intensity * w * 0.10f
                val beatAlpha = (intensity * 120).toInt().coerceIn(0, 140)

                hpGradientColors[0] = Color.argb(beatAlpha, gr, gg, gb)
                hpGradientColors[1] = Color.argb((beatAlpha * 0.3f).toInt(), gr, gg, gb)
                hpGradientColors[2] = Color.argb(0, gr, gg, gb)
                headphonePaint.shader = RadialGradient(
                    hpX, hpY, beatRadius,
                    hpGradientColors,
                    hpGradientStops,
                    Shader.TileMode.CLAMP
                )
                canvas.drawCircle(hpX, hpY, beatRadius, headphonePaint)
                headphonePaint.shader = null

                // Pulse ring
                val ringAlpha = (intensity * 50).toInt()
                headphonePaint.style = Paint.Style.STROKE
                headphonePaint.strokeWidth = 2.5f
                headphonePaint.color = Color.argb(ringAlpha, gr, gg, gb)
                val ringRadius = beatRadius * (0.7f + sin((animationPhase * 4f).toDouble()).toFloat() * 0.3f)
                canvas.drawCircle(hpX, hpY, ringRadius, headphonePaint)
                headphonePaint.style = Paint.Style.FILL
            }
        }
    }
}
