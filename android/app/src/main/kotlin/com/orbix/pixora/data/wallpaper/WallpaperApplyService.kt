package com.orbix.pixora.data.wallpaper

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Applies a static wallpaper from a remote URL to the system.
 *
 * v1 went through a Flutter MethodChannel → MainActivity → WallpaperManager
 * trip. v2 is one Kotlin file: download the bitmap, hand it to
 * WallpaperManager. No service, no IPC, no Surface conflict (those concerns
 * only matter for LIVE wallpapers; static API is synchronous and trivial).
 *
 * On Android N+ we apply to both HOME and LOCK in a single call. Older
 * devices only have the system wallpaper slot — same call, same result.
 */
sealed class ApplyResult {
    data object Success : ApplyResult()
    data class Error(val message: String) : ApplyResult()
}

@Singleton
class WallpaperApplyService @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    /**
     * @param isPanoramic when true, scale the bitmap to screen height and
     *  pass NO crop hint so Android keeps the full width — then home swipe
     *  scrolls through the wallpaper (Android auto-handles the offset).
     *  When false (or unknown), apply normally and let Android center-crop.
     */
    suspend fun applyFromUrl(url: String, isPanoramic: Boolean = false): ApplyResult =
        withContext(Dispatchers.IO) {
            runCatching {
                val raw = downloadBitmap(url)
                    ?: return@runCatching ApplyResult.Error("No se pudo decodificar la imagen")

                val wm = WallpaperManager.getInstance(context)
                val finalBitmap = if (isPanoramic) scaleToScreenHeight(raw) else raw

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    val flags = WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK
                    val visibleCrop: Rect? = if (isPanoramic) {
                        // Initial visible portion = leftmost screen-width slice;
                        // Android scrolls right as the user swipes home pages.
                        val (sw, _) = screenDims()
                        Rect(0, 0, sw, finalBitmap.height)
                    } else null
                    wm.setBitmap(finalBitmap, visibleCrop, true, flags)
                } else {
                    @Suppress("DEPRECATION")
                    wm.setBitmap(finalBitmap)
                }
                ApplyResult.Success
            }.getOrElse { e ->
                ApplyResult.Error(e.message ?: "Error desconocido al aplicar")
            }
        }

    /**
     * Scale panoramic bitmap so its height matches screen height. Width
     * scales proportionally — staying wider than screen so swipe scrolls
     * the wallpaper. Avoids passing a 4192x1024 image when the device is
     * only ~1080x2400 (massive memory waste + WallpaperManager rescales
     * anyway).
     */
    private fun scaleToScreenHeight(src: Bitmap): Bitmap {
        val (_, sh) = screenDims()
        if (src.height == sh) return src
        val ratio = sh.toFloat() / src.height.toFloat()
        val newW = (src.width * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, newW, sh, true)
    }

    /** Returns (width, height) in pixels of the default display. */
    private fun screenDims(): Pair<Int, Int> {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        return metrics.widthPixels to metrics.heightPixels
    }

    private fun downloadBitmap(url: String): Bitmap? {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = true
        }
        return try {
            conn.inputStream.use { BitmapFactory.decodeStream(it) }
        } finally {
            conn.disconnect()
        }
    }
}
