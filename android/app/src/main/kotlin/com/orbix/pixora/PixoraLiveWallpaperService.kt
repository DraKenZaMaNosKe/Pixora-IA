package com.orbix.pixora

import android.media.MediaPlayer
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import java.io.File

/**
 * Minimal looping video live wallpaper.
 *
 * Plays the file at `cacheDir/current_live.mp4`. Set by
 * [com.orbix.pixora.data.wallpaper.LiveApplyService] before launching
 * the system picker, so by the time Android starts our service the
 * file is already there.
 *
 * Lifecycle:
 *   - onSurfaceCreated → build a MediaPlayer, attach to Surface, loop, mute.
 *   - onVisibilityChanged → pause/resume so we don't burn battery while
 *     the user is on another screen.
 *   - onSurfaceDestroyed → release the MediaPlayer (otherwise codec leaks).
 *
 * Manifest must declare android:process=":wallpaper" so we have an
 * isolated process — the legacy WallpaperService Surface producer-conflict
 * pitfall (Canvas vs MediaPlayer on the same Surface) is the canonical
 * reason for this isolation. v2 alpha only uses MediaPlayer, but we
 * keep the process isolation so the canvas-based renderers can join
 * later without breaking each other.
 */
class PixoraLiveWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = LoopEngine()

    inner class LoopEngine : Engine() {
        private var player: MediaPlayer? = null

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            startPlayer(holder)
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            stopPlayer()
            super.onSurfaceDestroyed(holder)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            val p = player ?: return
            runCatching {
                if (visible) p.start() else p.pause()
            }
        }

        private fun startPlayer(holder: SurfaceHolder) {
            val file = File(cacheDir, CURRENT_LIVE_FILE)
            if (!file.exists()) return
            stopPlayer()
            runCatching {
                player = MediaPlayer().apply {
                    setDataSource(file.absolutePath)
                    setSurface(holder.surface)
                    isLooping = true
                    setVolume(0f, 0f)
                    setOnPreparedListener {
                        runCatching { it.start() }
                    }
                    prepareAsync()
                }
            }.onFailure {
                player = null
            }
        }

        private fun stopPlayer() {
            runCatching {
                player?.stop()
                player?.release()
            }
            player = null
        }
    }

    companion object {
        /** Name of the staged video file inside the app's cacheDir. */
        const val CURRENT_LIVE_FILE = "current_live.mp4"
    }
}
