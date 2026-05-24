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
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
            LinearProgressIndicator(
                progress = { state.progress },
                color = accent,
                trackColor = accent.copy(alpha = 0.2f),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(3.dp),
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
                        text = formatProgress(state.positionMs, state.durationMs),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
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
}
