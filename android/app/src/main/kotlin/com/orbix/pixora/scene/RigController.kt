package com.orbix.pixora.scene

import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import com.orbix.pixora.renderers.SpriteSheet

/**
 * Draws a bone-rigged character: parts joined hierarchically by parent/pivot,
 * animated by per-bone keyframes over a loop.
 *
 * Each frame, per bone (in topological order — parents first):
 *   L_b = T(pivot+delta) · R(rot) · S(scale) · T(-pivot)       (character space)
 *   W_b = W_parent · L_b     (root: W_root = G · L_root)
 * where G maps character space -> screen (anchor + scale + subjectFactor).
 * A part's bitmap starts at its crop offset, so its draw matrix is
 *   D = W_b · T(offset).
 *
 * Design: docs/superpowers/specs/2026-07-25-bone-rigging-2d-design.md
 * Zero allocations per frame — every matrix is pre-allocated.
 */
class RigController(
    private val rig: RigDef,
    private val sheets: Map<String, SpriteSheet>,
) {
    private companion object {
        const val TARGET_W = 1080f
        const val TARGET_H = 2340f
    }

    /** z within the scene's layer/sprite interleaving. */
    val z: Int get() = rig.z

    // Bones ordered parents-before-children so a parent's world matrix is
    // already fresh when its children compose against it.
    private val ordered: List<BoneDef> = topoSort(rig.bones)
    // Bones that draw a part, in their own z order.
    private val drawList: List<BoneDef> =
        rig.bones.filter { it.sprite != null }.sortedBy { it.z }
    // Per-bone world matrix (pre-allocated, reused every frame).
    private val world: Map<String, Matrix> =
        rig.bones.associate { it.id to Matrix() }

    private val local = Matrix()
    private val global = Matrix()
    private val drawMat = Matrix()
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val startNs = System.nanoTime()
    private val rootPivot: Pair<Float, Float> =
        ordered.firstOrNull { it.parent == null }?.pivotPx ?: (0f to 0f)

    fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int) {
        if (surfaceW <= 0 || surfaceH <= 0) return
        val phase = ((((System.nanoTime() - startNs) / 1_000_000L) % (rig.loopSeconds * 1000).toLong())
            .toFloat() / (rig.loopSeconds * 1000f)).coerceIn(0f, 1f)

        // Global: character space -> screen.
        val f = minOf(surfaceW / TARGET_W, surfaceH / TARGET_H)
        val k = rig.scale * f
        val ax = surfaceW / 2f + (rig.anchor.first - 0.5f) * TARGET_W * f
        val ay = surfaceH / 2f + (rig.anchor.second - 0.5f) * TARGET_H * f
        global.reset()
        global.postTranslate(-rootPivot.first, -rootPivot.second)
        global.postScale(k, k)
        global.postTranslate(ax, ay)

        // Compose world matrices (topological order).
        for (b in ordered) {
            sampleLocal(b, phase, local)
            val w = world[b.id] ?: continue
            w.set(local)
            val parentW = b.parent?.let { world[it] }
            w.postConcat(parentW ?: global)
        }

        // Draw parts in z order.
        for (b in drawList) {
            val bmp = (sheets[b.sprite] ?: continue).currentBitmap() ?: continue
            val w = world[b.id] ?: continue
            drawMat.reset()
            drawMat.postTranslate(b.offsetPx.first, b.offsetPx.second)
            drawMat.postConcat(w)
            canvas.drawBitmap(bmp, drawMat, paint)
        }
    }

    /** Fill [out] with the bone's local (character-space) matrix at [phase]. */
    private fun sampleLocal(b: BoneDef, phase: Float, out: Matrix) {
        var dx = 0f; var dy = 0f; var rot = 0f; var s = 1f
        val kf = b.keyframes
        if (kf.isNotEmpty()) {
            var i = 0
            while (i < kf.size - 1 && phase >= kf[i + 1].t) i++
            val a = kf[i]
            val c = if (i + 1 < kf.size) kf[i + 1] else kf[i]
            val span = c.t - a.t
            var u = if (span > 1e-5f) (phase - a.t) / span else 0f
            u = u.coerceIn(0f, 1f)
            if (rig.easing == "smooth") u = u * u * (3f - 2f * u)
            dx = a.x + (c.x - a.x) * u
            dy = a.y + (c.y - a.y) * u
            rot = a.rotation + (c.rotation - a.rotation) * u
            s = a.scale + (c.scale - a.scale) * u
        }
        out.reset()
        out.postTranslate(-b.pivotPx.first, -b.pivotPx.second)
        out.postScale(s, s)
        out.postRotate(rot)
        out.postTranslate(b.pivotPx.first + dx, b.pivotPx.second + dy)
    }

    private fun topoSort(bones: List<BoneDef>): List<BoneDef> {
        val byId = bones.associateBy { it.id }
        val out = mutableListOf<BoneDef>()
        val seen = HashSet<String>()
        fun visit(b: BoneDef) {
            if (b.id in seen) return
            b.parent?.let { byId[it] }?.let { if (it.id !in seen) visit(it) }
            seen.add(b.id)
            out.add(b)
        }
        for (b in bones) visit(b)
        return out
    }
}
