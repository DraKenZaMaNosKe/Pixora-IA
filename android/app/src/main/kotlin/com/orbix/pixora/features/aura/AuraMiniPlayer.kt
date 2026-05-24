package com.orbix.pixora.features.aura

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccessTime
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.RepeatOne
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.orbix.pixora.data.aura.AuraPlayerService
import com.orbix.pixora.data.aura.AuraPlayerState
import com.orbix.pixora.ui.components.SacredMandala
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

/**
 * Persistent mini-player anchored above the bottom bar. Visible whenever
 * a track is loaded in [AuraPlayerService] regardless of which tab is open.
 *
 * Uses its own Hilt ViewModel that reads from the same singleton
 * AuraPlayerService — so when you tap a frequency in AURA tab and then
 * switch to Wallpapers, this stays at the bottom.
 */
@Composable
fun AuraMiniPlayer(
    modifier: Modifier = Modifier,
    viewModel: AuraMiniPlayerViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val track = state.nowPlaying

    AnimatedVisibility(
        visible = track != null,
        enter = slideInVertically { it },
        exit = slideOutVertically { it },
        modifier = modifier,
    ) {
        if (track == null) return@AnimatedVisibility
        val accent = runCatching {
            Color(android.graphics.Color.parseColor(track.accentHex))
        }.getOrDefault(MaterialTheme.colorScheme.primary)

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
        ) {
            // Scrubber slider — replaces the static progress bar
            Slider(
                value = state.progress.coerceIn(0f, 1f),
                onValueChange = { v ->
                    val ms = (v * state.durationMs).toLong()
                    viewModel.seekTo(ms)
                },
                colors = SliderDefaults.colors(
                    thumbColor = accent,
                    activeTrackColor = accent,
                    inactiveTrackColor = accent.copy(alpha = 0.25f),
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(20.dp),
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                // Sacred Mandala badge — matches the same per-frequency
                // pattern in the AURA row, sized down for the mini-player.
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.size(44.dp),
                ) {
                    SacredMandala(
                        color = accent,
                        hz = track.hz,
                        isPlaying = state.isPlaying,
                        modifier = Modifier.fillMaxSize(),
                    )
                    if (track.hz != null) {
                        Text(
                            text = "${track.hz}",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Outlined.PlayArrow,
                            contentDescription = null,
                            tint = Color.White,
                        )
                    }
                }
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 12.dp)
                        .clickable { viewModel.togglePlayPause() },
                ) {
                    Text(
                        text = track.displayName,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                    )
                    Text(
                        text = if (state.sleepTimerMs != null)
                            "${formatProgress(state.positionMs, state.durationMs)}  ·  ⏱ ${formatTimer(state.sleepTimerMs)}"
                        else formatProgress(state.positionMs, state.durationMs),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                // Loop toggle
                IconButton(onClick = { viewModel.setLooping(!state.looping) }) {
                    Icon(
                        imageVector = if (state.looping) Icons.Outlined.RepeatOne else Icons.Outlined.Repeat,
                        contentDescription = "Repetir",
                        tint = if (state.looping) accent else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                // Sleep timer with dropdown
                SleepTimerButton(
                    accent = accent,
                    isActive = state.sleepTimerMs != null,
                    onSet = viewModel::setSleepTimer,
                    onCancel = viewModel::cancelSleepTimer,
                )
                // Play/pause
                IconButton(onClick = { viewModel.togglePlayPause() }) {
                    Icon(
                        imageVector = if (state.isPlaying) Icons.Outlined.Pause else Icons.Outlined.PlayArrow,
                        contentDescription = if (state.isPlaying) "Pausar" else "Reproducir",
                        tint = MaterialTheme.colorScheme.onSurface,
                    )
                }
                IconButton(onClick = { viewModel.stop() }) {
                    Icon(
                        imageVector = Icons.Outlined.Close,
                        contentDescription = "Cerrar",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun SleepTimerButton(
    accent: Color,
    isActive: Boolean,
    onSet: (Int) -> Unit,
    onCancel: () -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) {
            Icon(
                imageVector = Icons.Outlined.AccessTime,
                contentDescription = "Temporizador de sueño",
                tint = if (isActive) accent else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            listOf(15, 30, 45, 60).forEach { mins ->
                DropdownMenuItem(
                    text = { Text("$mins min") },
                    onClick = {
                        onSet(mins)
                        open = false
                    },
                )
            }
            if (isActive) {
                DropdownMenuItem(
                    text = { Text("Cancelar temporizador") },
                    onClick = {
                        onCancel()
                        open = false
                    },
                )
            }
        }
    }
}

private fun formatTimer(remainingMs: Long?): String {
    if (remainingMs == null) return ""
    val totalSec = (remainingMs / 1000).coerceAtLeast(0)
    val m = totalSec / 60
    val s = totalSec % 60
    return "%d:%02d".format(m, s)
}

private fun formatProgress(positionMs: Long, durationMs: Long): String {
    fun fmt(ms: Long): String {
        val total = (ms / 1000).coerceAtLeast(0)
        val m = total / 60
        val s = total % 60
        return "%d:%02d".format(m, s)
    }
    return "${fmt(positionMs)} / ${fmt(durationMs)}"
}

@HiltViewModel
class AuraMiniPlayerViewModel @Inject constructor(
    private val player: AuraPlayerService,
) : ViewModel() {
    val state: StateFlow<AuraPlayerState> = player.state
    fun togglePlayPause() = player.togglePlayPause()
    fun stop() = player.stop()
    fun seekTo(ms: Long) = player.seekTo(ms)
    fun setLooping(enabled: Boolean) = player.setLooping(enabled)
    fun setSleepTimer(minutes: Int) = player.setSleepTimer(minutes)
    fun cancelSleepTimer() = player.cancelSleepTimer()
}
