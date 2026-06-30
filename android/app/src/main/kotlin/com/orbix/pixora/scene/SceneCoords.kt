package com.orbix.pixora.scene

/**
 * Shared coordinate math for canvas scenes.
 * Mirrors tools/wallpapers/dashboard/scene_coords.js — keep both in sync.
 *
 * SPEC_NORM: sprite x/y in 0..1, top-left origin, y increases downward.
 */
object SceneCoords {
    const val REFERENCE_SURFACE_W = 1080
    const val REFERENCE_SURFACE_H = 2340

    fun coverFitScale(
        bmpW: Int,
        bmpH: Int,
        surfaceW: Int,
        surfaceH: Int,
        layerScale: Float = 1f,
    ): Float = maxOf(surfaceW.toFloat() / bmpW, surfaceH.toFloat() / bmpH) * layerScale

    fun layerLeftTop(
        bmpW: Int,
        bmpH: Int,
        surfaceW: Int,
        surfaceH: Int,
        layerScale: Float,
        offsetXPx: Float,
        offsetYPx: Float,
    ): Pair<Float, Float> {
        val scale = coverFitScale(bmpW, bmpH, surfaceW, surfaceH, layerScale)
        val drawW = bmpW * scale
        val drawH = bmpH * scale
        val left = (surfaceW - drawW) / 2f + offsetXPx
        val top = (surfaceH - drawH) / 2f + offsetYPx
        return left to top
    }

    /**
     * Bitmap-center draw point for SpriteSheet.drawAt when params.x/y mark the
     * anchor position (anchor_x/anchor_y default 0.5 = texture center).
     */
    fun spriteDrawCenter(
        xNorm: Float,
        yNorm: Float,
        anchorX: Float,
        anchorY: Float,
        targetW: Int,
        targetH: Int,
        surfaceW: Int,
        surfaceH: Int,
    ): Pair<Float, Float> {
        val cx = surfaceW * xNorm + (0.5f - anchorX) * targetW
        val cy = surfaceH * yNorm + (0.5f - anchorY) * targetH
        return cx to cy
    }
}