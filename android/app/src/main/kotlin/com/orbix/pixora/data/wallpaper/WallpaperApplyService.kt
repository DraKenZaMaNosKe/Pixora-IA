package com.orbix.pixora.data.wallpaper

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
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
     * Apply a wallpaper from URL.
     *
     * Per doc maestro §24.2-24.3 (4+ hours of v1 debug): Samsung One UI's
     * native panoramic scroll is reserved for ImageWallpaper set via
     * `WallpaperManager.setBitmap()`. The KEY insight is:
     *  - DO NOT scale the bitmap manually (Samsung scales the source).
     *  - DO NOT pass a visibleCropHint (overrides Samsung's auto-detection).
     *  - DO call `suggestDesiredDimensions` BEFORE setBitmap so the
     *    launcher knows it's a wide wallpaper.
     *  - DO apply panoramic with FLAG_SYSTEM only (no FLAG_LOCK — lock
     *    screen doesn't scroll).
     *
     * Aspect ratio must be >= 3:1 for Samsung to detect it as panoramic.
     * Pixora's official panoramic spec is 4192x1024 (4.09:1).
     */
    suspend fun applyFromUrl(url: String, isPanoramic: Boolean = false): ApplyResult =
        withContext(Dispatchers.IO) {
            runCatching {
                val bitmap = downloadBitmap(url)
                    ?: return@runCatching ApplyResult.Error("No se pudo decodificar la imagen")

                val wm = WallpaperManager.getInstance(context)

                if (isPanoramic) {
                    // Hint to Samsung's launcher that this wallpaper is
                    // wider than screen so home swipe scrolls it.
                    @Suppress("DEPRECATION")
                    runCatching {
                        wm.suggestDesiredDimensions(bitmap.width, bitmap.height)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        // FLAG_SYSTEM only — lock screen doesn't scroll, applying
                        // FLAG_LOCK to a panoramic crops it weirdly on the lockscreen.
                        wm.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)
                    } else {
                        @Suppress("DEPRECATION")
                        wm.setBitmap(bitmap)
                    }
                } else {
                    // Regular static wallpaper — apply to both screens.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        val flags = WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK
                        wm.setBitmap(bitmap, null, true, flags)
                    } else {
                        @Suppress("DEPRECATION")
                        wm.setBitmap(bitmap)
                    }
                }
                ApplyResult.Success
            }.getOrElse { e ->
                ApplyResult.Error(e.message ?: "Error desconocido al aplicar")
            }
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
