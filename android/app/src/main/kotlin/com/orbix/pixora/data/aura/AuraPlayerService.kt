package com.orbix.pixora.data.aura

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.orbix.pixora.data.models.AuraTrack
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * State exposed to the UI. Null `nowPlaying` means the player is idle.
 */
data class AuraPlayerState(
    val nowPlaying: AuraTrack? = null,
    val isPlaying: Boolean = false,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val looping: Boolean = false,
    /** Remaining millis on the sleep timer; null = no timer set. */
    val sleepTimerMs: Long? = null,
) {
    val progress: Float
        get() = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
}

/**
 * Single owner of the AURA ExoPlayer instance. The UI never touches the
 * player directly — it reads [state] and calls public methods.
 *
 * Mirrors v1's AuraPlayerService.instance pattern. v2 uses Media3 1.5
 * which subsumes ExoPlayer + MediaSession + just_audio's API surface.
 *
 * Position polling: we don't get a continuous position from ExoPlayer
 * for free — Player.Listener fires on state changes, not every frame. We
 * launch a tiny coroutine that polls every 500ms while playing. Cheap.
 */
@Singleton
class AuraPlayerService @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    private val _state = MutableStateFlow(AuraPlayerState())
    val state: StateFlow<AuraPlayerState> = _state.asStateFlow()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val player: ExoPlayer = ExoPlayer.Builder(context).build().apply {
        addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _state.value = _state.value.copy(
                    isPlaying = isPlaying,
                    durationMs = duration.coerceAtLeast(0L),
                )
                if (isPlaying) startPolling()
            }
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY) {
                    _state.value = _state.value.copy(durationMs = duration.coerceAtLeast(0L))
                }
            }
        })
    }

    private var pollingJob: kotlinx.coroutines.Job? = null
    private var sleepTimerJob: kotlinx.coroutines.Job? = null

    fun play(track: AuraTrack) {
        val current = _state.value.nowPlaying
        if (current?.id == track.id) {
            // Same track → toggle play/pause
            if (player.isPlaying) player.pause() else player.play()
            return
        }
        // New track → swap
        player.setMediaItem(MediaItem.fromUri(track.audioUrl))
        player.repeatMode = if (_state.value.looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
        player.prepare()
        player.play()
        _state.value = _state.value.copy(nowPlaying = track, positionMs = 0L)
    }

    fun togglePlayPause() {
        if (_state.value.nowPlaying == null) return
        if (player.isPlaying) player.pause() else player.play()
    }

    fun stop() {
        player.stop()
        player.clearMediaItems()
        pollingJob?.cancel()
        _state.value = AuraPlayerState()
    }

    fun seekTo(ms: Long) {
        player.seekTo(ms.coerceIn(0L, player.duration.coerceAtLeast(0L)))
        _state.value = _state.value.copy(positionMs = ms)
    }

    fun setLooping(enabled: Boolean) {
        player.repeatMode = if (enabled) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
        _state.value = _state.value.copy(looping = enabled)
    }

    /**
     * Start a sleep timer that pauses playback after [minutes].
     * Pass 0 (or call [cancelSleepTimer]) to clear an active timer.
     */
    fun setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        if (minutes <= 0) return
        val totalMs = minutes * 60_000L
        _state.value = _state.value.copy(sleepTimerMs = totalMs)
        sleepTimerJob = scope.launch {
            var remaining = totalMs
            while (remaining > 0) {
                delay(1000)
                remaining -= 1000
                _state.value = _state.value.copy(sleepTimerMs = remaining.coerceAtLeast(0))
            }
            // Time's up
            player.pause()
            _state.value = _state.value.copy(sleepTimerMs = null)
        }
    }

    fun cancelSleepTimer() {
        sleepTimerJob?.cancel()
        sleepTimerJob = null
        _state.value = _state.value.copy(sleepTimerMs = null)
    }

    private fun startPolling() {
        pollingJob?.cancel()
        pollingJob = scope.launch {
            while (player.isPlaying) {
                _state.value = _state.value.copy(
                    positionMs = player.currentPosition.coerceAtLeast(0L),
                    durationMs = player.duration.coerceAtLeast(0L),
                )
                delay(500)
            }
        }
    }
}
