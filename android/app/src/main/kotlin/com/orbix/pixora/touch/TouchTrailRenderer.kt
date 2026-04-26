package com.orbix.pixora.touch

import android.graphics.Canvas

/**
 * A user-selectable visual effect that draws over the wallpaper while the
 * user drags their finger across the screen.
 *
 * Implementations live in this package and are registered in
 * [TouchTrailRegistry]. The wallpaper engine forwards every touch event
 * via [onDown] / [onMove] and calls [draw] every render frame.
 *
 * The renderer is also given the wallpaper's `glowColor` (the user-picked
 * accent color from the catalog entry) so brand-tinted effects can use it
 * as a fallback color when none of their own palette is appropriate.
 */
interface TouchTrailRenderer {

    /** Stable identifier — also the SharedPreferences value. */
    val id: String

    /** Localized display name shown in the picker. */
    val displayName: String

    /** Whether ANY active particle/trail is currently being drawn.
     *  PixoraWallpaperService uses this to decide if it can drop to idle FPS. */
    val isActive: Boolean

    /** Touch began at (x, y) in surface pixels. */
    fun onDown(x: Float, y: Float)

    /** Touch moved to (x, y). Fires many times during a drag. */
    fun onMove(x: Float, y: Float)

    /** Touch ended (UP or CANCEL). Optional cleanup. */
    fun onUp() {}

    /**
     * Render this frame. Engine clears + draws background BEFORE this is
     * called, so the trail composes over the existing scene.
     *
     * @param glowColor user-picked accent color from the wallpaper entry,
     *                  in case the trail wants to tint particles with it.
     */
    fun draw(canvas: Canvas, surfaceW: Int, surfaceH: Int, tick: Long, glowColor: Int)

    /** Reset all internal state (drop history, clear particles). */
    fun reset()
}
