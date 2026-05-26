package com.orbix.pixora.data.wallpaper

import android.app.Activity
import android.app.ActivityManager
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Process
import com.orbix.pixora.PixoraStaticWallpaperService
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Applies a wallpaper from URL with two distinct paths:
 *
 * - **Standard (portrait) wallpapers** → `wm.setBitmap(bitmap, null, true, flag)`.
 *   Battle-tested in v1 for months. Samsung crops to 9:16, applies cleanly to
 *   home + lock as requested.
 *
 * - **Panoramic wallpapers** → custom WallpaperService route. We download the
 *   bitmap to cacheDir, write a pointer file, kill the :wallpaperstatic
 *   process (so Android respawns the engine fresh) and launch the system
 *   live-wallpaper picker pointed at [PixoraStaticWallpaperService]. The user
 *   confirms with "Set wallpaper" inside the picker, and from that moment the
 *   wallpaper scrolls horizontally on home-screen swipes — driven by
 *   onOffsetsChanged inside the service. This is the only approach that
 *   actually scrolls on Samsung A15+ / One UI; the naïve setBitmap path
 *   stores the wide bitmap correctly but the launcher never emits offsets to
 *   the system ImageWallpaper. Memory `tech_panoramic_scroll_via_custom_service`
 *   documents the empirical findings from v1.
 *
 * Standard path returns Success synchronously. Panoramic path returns
 * PickerLaunched (the apply isn't complete until the user taps "Set").
 */
sealed class ApplyResult {
    /** Standard apply finished — the wallpaper is set. */
    data object Success : ApplyResult()
    /** Panoramic path: bitmap staged + picker shown, awaiting user confirmation. */
    data object PickerLaunched : ApplyResult()
    data class Error(val message: String) : ApplyResult()
}

/** Which surface to apply the wallpaper to. */
enum class ApplyTarget(val flag: Int) {
    Home(WallpaperManager.FLAG_SYSTEM),
    Lock(WallpaperManager.FLAG_LOCK),
    Both(WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK),
}

@Singleton
class WallpaperApplyService @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    suspend fun applyFromUrl(
        url: String,
        isPanoramic: Boolean = false,
        activity: Activity? = null,
        target: ApplyTarget = ApplyTarget.Both,
    ): ApplyResult = withContext(Dispatchers.IO) {
        if (isPanoramic && activity != null) {
            applyPanoramic(url, activity)
        } else {
            applyStandard(url, target)
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // Standard path (works for portrait wallpapers, fails for panoramics)
    // ────────────────────────────────────────────────────────────────────────

    private fun applyStandard(url: String, target: ApplyTarget): ApplyResult =
        runCatching {
            val bitmap = downloadBitmap(url)
                ?: return@runCatching ApplyResult.Error("No se pudo decodificar la imagen")
            val ratio = bitmap.width.toFloat() / bitmap.height
            println("[WallpaperApplyService] standard apply: ${bitmap.width}x${bitmap.height} ratio ${"%.2f".format(ratio)} target=$target")

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

    // ────────────────────────────────────────────────────────────────────────
    // Panoramic path (downloads, stages, kills service process, launches picker)
    // ────────────────────────────────────────────────────────────────────────

    private suspend fun applyPanoramic(url: String, activity: Activity): ApplyResult {
        val staged = runCatching { downloadToCache(url) }.getOrElse {
            return ApplyResult.Error("No se pudo descargar el panorámico: ${it.message}")
        }
        if (!staged.exists() || staged.length() == 0L) {
            return ApplyResult.Error("Panorámico no quedó en cache")
        }
        // Write the pointer file the service reads on startup.
        File(context.cacheDir, PixoraStaticWallpaperService.CURRENT_STATIC_POINTER)
            .writeText(staged.absolutePath)
        println("[WallpaperApplyService] panoramic staged: ${staged.absolutePath} (${staged.length()} bytes)")

        // Kill the static-wallpaper process so Android respawns the engine
        // with a fresh Surface that loads the just-staged bitmap. Without
        // this, an old engine instance keeps showing the previous wallpaper
        // until the user re-enters home screen.
        killWallpaperProcess(WALLPAPER_STATIC_PROCESS)
        delay(150) // beat for Android to register the kill

        withContext(Dispatchers.Main) { launchPicker(activity) }
        return ApplyResult.PickerLaunched
    }

    private fun downloadToCache(url: String): File {
        val target = File(context.cacheDir, "current_panoramic.bin")
        val tmp = File(context.cacheDir, "current_panoramic.bin.tmp")
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 60_000
            instanceFollowRedirects = true
        }
        try {
            conn.inputStream.use { input ->
                tmp.outputStream().use { out -> input.copyTo(out) }
            }
            if (target.exists()) target.delete()
            if (!tmp.renameTo(target)) {
                tmp.copyTo(target, overwrite = true)
                tmp.delete()
            }
            return target
        } finally {
            conn.disconnect()
        }
    }

    private fun killWallpaperProcess(targetSuffix: String) {
        runCatching {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val pkg = context.packageName
            val target = "$pkg:$targetSuffix"
            am.runningAppProcesses?.forEach { proc ->
                if (proc.processName == target) {
                    println("[WallpaperApplyService] killing $target pid=${proc.pid}")
                    Process.killProcess(proc.pid)
                }
            }
        }.onFailure {
            println("[WallpaperApplyService] killWallpaperProcess failed: ${it.message}")
        }
    }

    private fun launchPicker(activity: Activity) {
        val component = ComponentName(activity, PixoraStaticWallpaperService::class.java)
        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).apply {
            putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
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

    companion object {
        /** Process suffix for the static/panoramic wallpaper service. */
        private const val WALLPAPER_STATIC_PROCESS = "wallpaperstatic"
    }
}
