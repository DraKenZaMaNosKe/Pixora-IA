package com.orbix.pixora.data.wallpaper

import android.app.Activity
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
 * Applies a wallpaper from URL — port of v1's setWallpaper (Pixora
 * Flutter branch `play-store-estable`, MainActivity.kt L690-718 +
 * static_wallpaper_installer.dart).
 *
 * v1 pattern (battle-tested for months in production):
 *  1. Download bitmap with original extension (webp/jpg/png).
 *  2. `BitmapFactory.decodeFile/decodeStream` — Android handles all
 *     three formats natively.
 *  3. `wm.setBitmap(bitmap, null, true, flag)` direct, NO picker,
 *     NO FileProvider, NO suggestDesiredDimensions, NO setStream.
 *  4. Samsung One UI's compositor auto-detects panoramic by aspect
 *     ratio >= 3:1 and enables home-page horizontal scroll.
 *
 * Key insight (the bit I missed earlier): panoramic must be applied
 * to FLAG_SYSTEM only — NOT FLAG_LOCK too. Applying a wide wallpaper
 * to the lock screen forces Samsung to crop to 9:16 which kills the
 * panoramic dimensions in the system wallpaper too.
 *
 * Non-panoramic wallpapers go to both screens as before.
 */
sealed class ApplyResult {
    data object Success : ApplyResult()
    data class Error(val message: String) : ApplyResult()
}

/** Which surface to apply the wallpaper to — matches v1's target int. */
enum class ApplyTarget(val flag: Int) {
    Home(WallpaperManager.FLAG_SYSTEM),
    Lock(WallpaperManager.FLAG_LOCK),
    Both(WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK),
}

@Singleton
class WallpaperApplyService @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    @Suppress("UNUSED_PARAMETER")
    suspend fun applyFromUrl(
        url: String,
        isPanoramic: Boolean = false,
        activity: Activity? = null,
        target: ApplyTarget = ApplyTarget.Both,
    ): ApplyResult = withContext(Dispatchers.IO) {
        runCatching {
            val bitmap = downloadBitmap(url)
                ?: return@runCatching ApplyResult.Error("No se pudo decodificar la imagen")
            val ratio = bitmap.width.toFloat() / bitmap.height
            println("[WallpaperApplyService] apply: ${bitmap.width}x${bitmap.height} ratio ${"%.2f".format(ratio)} target=$target panoramic=$isPanoramic")

            val wm = WallpaperManager.getInstance(context)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                wm.setBitmap(bitmap, null, true, target.flag)
            } else {
                @Suppress("DEPRECATION")
                wm.setBitmap(bitmap)
            }
            bitmap.recycle()
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
