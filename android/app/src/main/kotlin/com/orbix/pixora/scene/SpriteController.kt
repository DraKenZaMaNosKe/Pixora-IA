package com.orbix.pixora.scene

import android.graphics.Canvas
import com.orbix.pixora.renderers.SpriteSheet
import kotlin.math.cos
import kotlin.math.sin

/**
 * Animates a SpriteSheet according to a behavior declared in the scene
 * spec. Each behavior has its own controller; new behaviors are added by
 * subclassing and registering in CanvasSceneRenderer.
 */
sealed class SpriteController(val def: SpriteDef, val sheet: SpriteSheet) {

    abstract fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long)

    /** Default-facing helper — flip when motion direction != sprite's native facing. */
    protected fun flipFor(motionRight: Boolean): Boolean =
        if (def.defaultFacing == "right") !motionRight else motionRight

    companion object {
        fun create(def: SpriteDef, sheet: SpriteSheet): SpriteController? {
            return when (def.behavior) {
                "orbit" -> OrbitController(def, sheet)
                "wander" -> WanderController(def, sheet)
                "translate" -> TranslateController(def, sheet)
                "static" -> StaticController(def, sheet)
                "preload" -> PreloadController(def, sheet)
                else -> null
            }
        }
    }
}

/** Loads the sprite into memory but draws nothing. Used to make a sprite
 *  available to events (phoenix, lightning, bat_swarm) without rendering
 *  it as a regular sprite layer. */
class PreloadController(def: SpriteDef, sheet: SpriteSheet) :
    SpriteController(def, sheet) {
    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        // intentionally empty — sprite frame timer doesn't even need to advance
        // since events that USE this sprite call sheet.advance() themselves
    }
}

/**
 * Sprite orbits an ellipse centered at (cx, cy) with radii (radius_x,
 * radius_y). Angular speed in radians per tick.
 *
 * params: cx, cy, radius_x, radius_y, angular_speed, scale, alpha
 *         start_angle (optional)
 */
class OrbitController(def: SpriteDef, sheet: SpriteSheet) :
    SpriteController(def, sheet) {

    private val cx = def.params.f("cx", 0.5f)
    private val cy = def.params.f("cy", 0.5f)
    private val rx = def.params.f("radius_x", 0.3f)
    private val ry = def.params.f("radius_y", rx * 0.6f)
    private val angularSpeed = def.params.f("angular_speed", 0.012f)
    private val scale = def.params.f("scale", 0.0014f)
    private val alpha = def.params.i("alpha", 255)
    private var angle = def.params.f("start_angle", 0f)

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        sheet.advance()
        angle += angularSpeed
        val x = surfaceW * cx + cos(angle.toDouble()).toFloat() * surfaceW * rx
        val y = surfaceH * cy + sin(angle.toDouble()).toFloat() * surfaceH * ry
        // Horizontal motion direction: vx ∝ -sin(angle) * angularSpeed
        // Moving right when angularSpeed * sin(angle) < 0
        val movingRight = angularSpeed * sin(angle.toDouble()) < 0
        sheet.drawAt(canvas, x, y,
            scale = SceneCoords.REFERENCE_SURFACE_W * scale *
                SceneCoords.subjectFactor(surfaceW, surfaceH),
            flipX = flipFor(movingRight),
            alpha = alpha)
    }
}

/**
 * Sprite gently drifts around a set of fixed anchor points, picking up
 * subtle sinusoidal offsets so it feels alive.
 *
 * params: anchors:[[x,y],...], wander_amplitude:[ax,ay], scale, alpha
 */
class WanderController(def: SpriteDef, sheet: SpriteSheet) :
    SpriteController(def, sheet) {

    private val anchors = def.params.vec2List("anchors")
    private val amp = def.params.vec2("wander_amplitude", 0.04f to 0.02f)
    private val scale = def.params.f("scale", 0.0010f)
    private val alpha = def.params.i("alpha", 255)

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        if (anchors.isEmpty()) return
        sheet.advance()
        for ((i, p) in anchors.withIndex()) {
            val phase = tick * 0.02f + i * 1.3f
            val ox = sin(phase.toDouble()).toFloat() * surfaceW * amp.first
            val oy = cos((phase * 1.4).toDouble()).toFloat() * surfaceH * amp.second
            val bx = surfaceW * p.first + ox
            val by = surfaceH * p.second + oy
            sheet.drawAt(canvas, bx, by,
                scale = SceneCoords.REFERENCE_SURFACE_W * scale *
                SceneCoords.subjectFactor(surfaceW, surfaceH),
                flipX = flipFor(i % 2 == 0),
                alpha = alpha)
        }
    }
}

/**
 * Sprite linearly translates between two normalized points, looping.
 * Useful for an owl crossing the screen, a fish swimming straight.
 *
 * params: from:[x,y], to:[x,y], duration_s, scale, alpha
 */
class TranslateController(def: SpriteDef, sheet: SpriteSheet) :
    SpriteController(def, sheet) {

    private val from = def.params.vec2("from", -0.1f to 0.5f)
    private val to = def.params.vec2("to", 1.1f to 0.5f)
    private val durationTicks = (def.params.f("duration_s", 22f) * 60f).coerceAtLeast(60f)
    private val scale = def.params.f("scale", 0.0009f)
    private val alpha = def.params.i("alpha", 255)
    private val movingRight = to.first > from.first

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        sheet.advance()
        val t = (tick % durationTicks.toLong()) / durationTicks
        val x = (from.first + (to.first - from.first) * t) * surfaceW
        val y = (from.second + (to.second - from.second) * t) * surfaceH
        sheet.drawAt(canvas, x, y,
            scale = SceneCoords.REFERENCE_SURFACE_W * scale *
                SceneCoords.subjectFactor(surfaceW, surfaceH),
            flipX = flipFor(movingRight),
            alpha = alpha)
    }
}

/**
 * Sprite stays in place; only the frame animates.
 *
 * params: x, y, scale, alpha
 *         fullscreen (bool, default false) — if true, the sprite is
 *           scaled to FILL the surface (e.g. anime cockpit overlay)
 *           and x/y/scale are ignored.
 */
class StaticController(def: SpriteDef, sheet: SpriteSheet) :
    SpriteController(def, sheet) {

    private val x = def.params.f("x", 0.5f)
    private val y = def.params.f("y", 0.5f)
    private val anchorX = def.params.f("anchor_x", 0.5f)
    private val anchorY = def.params.f("anchor_y", 0.5f)
    private val scale = def.params.f("scale", 0.0010f)
    private val alpha = def.params.i("alpha", 255)
    private val flipX = def.params.b("flip_x", false)
    private val fullscreen = def.params.b("fullscreen", false)
    // 2026-07-04 — offset in TARGET (1080×2340) pixels, scaled by
    // subjectFactor at draw time. Lets a sprite inherit the same
    // positioning nudge its parent image_layer received in the sprite
    // editor (e.g. Morrigan hair follows Morrigan's +40/+166 offset).
    private val offsetXPx = def.params.f("offset_x_px", 0f)
    private val offsetYPx = def.params.f("offset_y_px", 0f)

    override fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long) {
        sheet.advance()
        if (fullscreen) {
            // Fill the entire surface — sprite drawn centered, scaled to
            // the larger of (surfaceW/bmpW, surfaceH/bmpH) so it covers.
            val bmpW = sheet.width.coerceAtLeast(1)
            val bmpH = sheet.height.coerceAtLeast(1)
            val sx = surfaceW.toFloat() / bmpW
            val sy = surfaceH.toFloat() / bmpH
            val s = maxOf(sx, sy)
            // Pre-scale once to surface dims — fullscreen sprites benefit
            // the most since they have the largest per-frame draw cost.
            sheet.ensurePrescaled((bmpW * s).toInt(), (bmpH * s).toInt())
            sheet.drawAt(canvas, surfaceW / 2f, surfaceH / 2f,
                scale = s, flipX = flipX, alpha = alpha)
        } else {
            // Positioned sprite (e.g. Pikachu, chimenea fire) — pre-scale
            // the frames to their final on-screen size so per-frame draw
            // becomes a pure blit (no GPU bilinear filter, no matrix scale).
            //
            // 2026-07-04 — scale by REFERENCE_W × subjectFactor so the sprite
            // shrinks in sync with its subject on shorter viewports (Huawei
            // 1920) instead of staying visually oversized. Same factor as
            // image_layers use in CanvasSceneRenderer.ensureLayersPrescaled.
            val factor = SceneCoords.subjectFactor(surfaceW, surfaceH)
            val finalScale = SceneCoords.REFERENCE_SURFACE_W * scale * factor
            val targetW = (sheet.width * finalScale).toInt().coerceAtLeast(1)
            val targetH = (sheet.height * finalScale).toInt().coerceAtLeast(1)
            sheet.ensurePrescaled(targetW, targetH)
            val (drawCx, drawCy) = SceneCoords.spriteDrawCenter(
                x, y, anchorX, anchorY, targetW, targetH, surfaceW, surfaceH,
            )
            sheet.drawAt(canvas,
                drawCx + offsetXPx * factor,
                drawCy + offsetYPx * factor,
                scale = finalScale,
                flipX = flipX, alpha = alpha)
        }
    }
}
