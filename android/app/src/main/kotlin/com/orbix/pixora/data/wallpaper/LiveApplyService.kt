package com.orbix.pixora.data.wallpaper

import android.app.Activity
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import com.orbix.pixora.PixoraLiveWallpaperService
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

sealed class LiveApplyResult {
    /** Successfully staged the video AND launched the system picker. */
    data object PickerLaunched : LiveApplyResult()
    data class Error(val message: String) : LiveApplyResult()
}

/**
 * End-to-end live wallpaper apply.
 *
 * 1. Downloads the MP4 to `cacheDir/current_live.mp4` (overwrites any
 *    previous live wallpaper file). Same file the PixoraLiveWallpaperService
 *    will play once Android starts our engine.
 * 2. Launches the system live-wallpaper picker pointed at our service
 *    component. The user confirms with "Set wallpaper" inside the picker.
 *
 * We don't call WallpaperManager.setWallpaperComponent directly because
 * it requires SET_WALLPAPER_COMPONENT permission which is system-level.
 * The picker intent is the user-blessed equivalent — Android shows the
 * preview, user taps Set, and Android wires it up.
 */
@Singleton
class LiveApplyService @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    suspend fun stageAndLaunch(videoUrl: String, activity: Activity): LiveApplyResult =
        withContext(Dispatchers.IO) {
            val staged = runCatching { downloadToCache(videoUrl) }.getOrElse {
                return@withContext LiveApplyResult.Error(
                    "No se pudo descargar el video: ${it.message}",
                )
            }
            if (!staged.exists() || staged.length() == 0L) {
                return@withContext LiveApplyResult.Error("Video no quedó en cache")
            }
            withContext(Dispatchers.Main) { launchPicker(activity) }
            LiveApplyResult.PickerLaunched
        }

    private fun downloadToCache(url: String): File {
        val target = File(context.cacheDir, PixoraLiveWallpaperService.CURRENT_LIVE_FILE)
        val tmp = File(context.cacheDir, "${PixoraLiveWallpaperService.CURRENT_LIVE_FILE}.tmp")
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 60_000
            instanceFollowRedirects = true
        }
        try {
            conn.inputStream.use { input ->
                tmp.outputStream().use { out ->
                    input.copyTo(out)
                }
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

    private fun launchPicker(activity: Activity) {
        val component = ComponentName(activity, PixoraLiveWallpaperService::class.java)
        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).apply {
            putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }
}
