package com.orbix.pixora.data.ringtones

import android.content.Context
import android.media.MediaPlayer
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Tiny MediaPlayer wrapper for ringtone preview clips (≤30s).
 *
 * Why not ExoPlayer like AURA? These previews are short remote MP3s with
 * no need for sessions, notifications, background playback, scrubbing,
 * looping, etc. The classic MediaPlayer covers it in 20 lines.
 *
 * Only one preview plays at a time — switching tones stops the current
 * one and starts the new one. Tapping the same tone toggles stop.
 */
@Singleton
class RingtonePreviewPlayer @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val _nowPlayingId = MutableStateFlow<String?>(null)
    val nowPlayingId: StateFlow<String?> = _nowPlayingId.asStateFlow()

    private var player: MediaPlayer? = null

    /** Tap behavior: if [toneId] is already playing, stop. Otherwise switch. */
    fun toggle(toneId: String, url: String) {
        if (_nowPlayingId.value == toneId) {
            stop()
            return
        }
        playFresh(toneId, url)
    }

    fun stop() {
        runCatching {
            player?.stop()
            player?.release()
        }
        player = null
        _nowPlayingId.value = null
    }

    private fun playFresh(toneId: String, url: String) {
        stop()
        runCatching {
            player = MediaPlayer().apply {
                setDataSource(url)
                setOnPreparedListener { it.start() }
                setOnCompletionListener {
                    if (_nowPlayingId.value == toneId) {
                        _nowPlayingId.value = null
                    }
                    it.release()
                    if (player == it) player = null
                }
                setOnErrorListener { mp, _, _ ->
                    if (_nowPlayingId.value == toneId) _nowPlayingId.value = null
                    mp.release()
                    if (player == mp) player = null
                    true
                }
                prepareAsync()
            }
            _nowPlayingId.value = toneId
        }.onFailure {
            println("[RingtonePreviewPlayer] preview failed: ${it.message}")
            _nowPlayingId.value = null
        }
    }
}
