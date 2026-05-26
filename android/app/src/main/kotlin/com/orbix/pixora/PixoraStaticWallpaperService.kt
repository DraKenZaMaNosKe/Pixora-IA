package com.orbix.pixora

import android.graphics.Canvas
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.util.Log
import android.view.SurfaceHolder
import java.io.File

/**
 * Static / panoramic image wallpaper service. Plays the bitmap file at
 * `cacheDir/current_static.path` (a small text file containing the absolute
 * path to the actual bitmap, written by WallpaperApplyService before
 * launching the live wallpaper picker).
 *
 * Delegates all the bitmap work — decoding, scaling, scroll math, recycling —
 * to [PanoramicWallpaperRenderer]. This service is intentionally tiny;
 * the orchestrator pattern is what we want to establish as the v2 baseline.
 *
 * Why custom service instead of `WallpaperManager.setBitmap`:
 *   Samsung One UI's system ImageWallpaper does NOT auto-pan wide bitmaps on
 *   home-screen swipes in most Samsung A-series firmwares (confirmed empirically
 *   on Samsung A15 / 2026-05-24, see v1 memory `tech_panoramic_scroll_via_custom_service`).
 *   The bitmap is stored correctly (`dumpsys wallpaper` shows `mCropHint=Rect(0,0-4128,1024)`)
 *   but the launcher never emits `onOffsetsChanged` to the system wallpaper.
 *   Our own service receives those offsets and pans manually on the Canvas.
 *
 * Lifecycle:
 *   - onSurfaceCreated → init renderer.
 *   - onSurfaceChanged → tell renderer the new dims + load current bitmap.
 *   - onOffsetsChanged → forward to renderer + redraw.
 *   - onVisibilityChanged(true) → reload current bitmap + redraw.
 *   - onSurfaceDestroyed → release renderer.
 *
 * Manifest must declare android:process=":wallpaper" so Canvas-based renderers
 * stay isolated from MediaPlayer-based ones (same Surface producer-conflict
 * pitfall documented in v1's PixoraWallpaperService class header).
 */
class PixoraStaticWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = StaticEngine()

    inner class StaticEngine : Engine() {

        private val renderer = PanoramicWallpaperRenderer(applicationContext)
        private val handler = Handler(Looper.getMainLooper())
        private var holder: SurfaceHolder? = null
        private var lastLoadedPath: String? = null

        // ~60 fps draw loop, only runs while the renderer is settling (scroll
        // interpolating). Idles when nothing is moving to save battery.
        private val frameIntervalMs = 16L
        private val settleRunnable = object : Runnable {
            override fun run() {
                if (renderer.tick()) {
                    redraw()
                }
                if (renderer.isSettling()) {
                    handler.postDelayed(this, frameIntervalMs)
                }
            }
        }

        private fun kickAnimation() {
            handler.removeCallbacks(settleRunnable)
            handler.post(settleRunnable)
        }

        override fun onCreate(surfaceHolder: SurfaceHolder?) {
            super.onCreate(surfaceHolder)
            // IMPORTANT: setOffsetNotificationsEnabled MUST be called from
            // Engine.onCreate, NOT from onSurfaceCreated. Calling it from
            // onSurfaceCreated triggers updateSurface() internally, which
            // re-fires onSurfaceCreated → infinite recursion → StackOverflow.
            // Calling it from onCreate (which runs BEFORE the surface is
            // created) is safe because updateSurface no-ops the first time.
            try { setOffsetNotificationsEnabled(true) } catch (_: Exception) {}
            Log.d(TAG, "Engine onCreate")
        }

        override fun onSurfaceCreated(surfaceHolder: SurfaceHolder) {
            super.onSurfaceCreated(surfaceHolder)
            holder = surfaceHolder
            Log.d(TAG, "Engine onSurfaceCreated")
        }

        override fun onSurfaceChanged(
            surfaceHolder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int,
        ) {
            super.onSurfaceChanged(surfaceHolder, format, width, height)
            holder = surfaceHolder
            Log.d(TAG, "Engine onSurfaceChanged ${width}x${height}")
            renderer.onSurfaceChanged(width, height)
            reloadAndRedraw()
        }

        override fun onOffsetsChanged(
            xOffset: Float,
            yOffset: Float,
            xStep: Float,
            yStep: Float,
            xPixelOffset: Int,
            yPixelOffset: Int,
        ) {
            Log.d(TAG, "onOffsetsChanged: xOffset=$xOffset xStep=$xStep panoramic=${renderer.isPanoramic} range=${renderer.scrollRangePx}")
            renderer.onOffsetsChanged(xOffset)
            // Kick the animation loop — it will interpolate scrollOffsetPx
            // toward the new target across multiple frames for smooth glide
            // even though Samsung only emits 1-2 events per swipe gesture.
            kickAnimation()
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            if (visible) reloadAndRedraw()
        }

        override fun onSurfaceDestroyed(surfaceHolder: SurfaceHolder) {
            holder = null
            super.onSurfaceDestroyed(surfaceHolder)
        }

        override fun onDestroy() {
            handler.removeCallbacks(settleRunnable)
            renderer.release()
            super.onDestroy()
        }

        // ──────────────────────────────────────────────────────────────────

        private fun reloadAndRedraw() {
            val pointer = File(cacheDir, CURRENT_STATIC_POINTER)
            if (!pointer.exists()) {
                Log.w(TAG, "reloadAndRedraw: no pointer file at $pointer")
                return
            }
            val path = pointer.readText().trim()
            if (path.isEmpty()) return
            if (path == lastLoadedPath) {
                // Same wallpaper, just request a redraw with current state.
                redraw()
                return
            }
            lastLoadedPath = path
            renderer.loadFromFile(path) { redraw() }
        }

        private fun redraw() {
            val h = holder ?: return
            if (!h.surface.isValid) return
            val canvas = try { h.lockCanvas() } catch (_: Exception) { null } ?: return
            try {
                canvas.drawColor(Color.BLACK)
                renderer.drawOn(canvas)
            } finally {
                try { h.unlockCanvasAndPost(canvas) } catch (_: Exception) {}
            }
        }
    }

    companion object {
        private const val TAG = "PixoraStaticWP"

        /**
         * Pointer file inside the app's cacheDir. Contains a single line: the
         * absolute path to the bitmap to render. WallpaperApplyService writes
         * this before launching the live wallpaper picker (or before calling
         * setWallpaperComponent if the service is already active).
         */
        const val CURRENT_STATIC_POINTER = "current_static.path"
    }
}
