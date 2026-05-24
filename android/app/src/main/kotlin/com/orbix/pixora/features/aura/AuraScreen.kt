package com.orbix.pixora.features.aura

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Forest
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.PlayCircleOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.orbix.pixora.data.models.AuraTrack

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuraScreen(
    viewModel: AuraViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val playerState by viewModel.playerState.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("AURA · Audio Wellness") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    titleContentColor = MaterialTheme.colorScheme.onBackground,
                ),
            )
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                state.loading && state.tracks.isEmpty() -> CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.errorMsg != null && state.tracks.isEmpty() -> Text(
                    text = state.errorMsg!!,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> AuraList(
                    state = state,
                    nowPlayingId = playerState.nowPlaying?.id,
                    isPlaying = playerState.isPlaying,
                    onTrackClick = viewModel::onTrackTapped,
                )
            }
        }
    }
}

@Composable
private fun AuraList(
    state: AuraUiState,
    nowPlayingId: String?,
    isPlaying: Boolean,
    onTrackClick: (AuraTrack) -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        if (state.frequencies.isNotEmpty()) {
            item { SectionHeader("Frecuencias Solfeggio", Icons.Outlined.GraphicEq) }
            items(state.frequencies, nowPlayingId, isPlaying, onTrackClick)
        }
        if (state.nature.isNotEmpty()) {
            item { SectionHeader("Naturaleza", Icons.Outlined.Forest) }
            items(state.nature, nowPlayingId, isPlaying, onTrackClick)
        }
        if (state.other.isNotEmpty()) {
            item { SectionHeader("Otros", Icons.Outlined.PlayCircleOutline) }
            items(state.other, nowPlayingId, isPlaying, onTrackClick)
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.items(
    tracks: List<AuraTrack>,
    nowPlayingId: String?,
    isPlaying: Boolean,
    onTrackClick: (AuraTrack) -> Unit,
) {
    items(tracks.size, key = { tracks[it].id }) { i ->
        val track = tracks[i]
        val isCurrent = track.id == nowPlayingId
        TrackRow(
            track = track,
            isCurrent = isCurrent,
            isPlaying = isCurrent && isPlaying,
        ) { onTrackClick(track) }
    }
}

@Composable
private fun SectionHeader(label: String, icon: ImageVector) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onBackground,
            modifier = Modifier.padding(start = 8.dp),
        )
    }
}

@Composable
private fun TrackRow(
    track: AuraTrack,
    isCurrent: Boolean,
    isPlaying: Boolean,
    onClick: () -> Unit,
) {
    val accent = runCatching { Color(android.graphics.Color.parseColor(track.accentHex)) }
        .getOrDefault(MaterialTheme.colorScheme.primary)
    val bgColor = if (isCurrent) accent.copy(alpha = 0.18f)
                  else MaterialTheme.colorScheme.surfaceVariant
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(bgColor)
            .clickable { onClick() }
            .padding(12.dp),
    ) {
        // Hz badge / play icon — when this row is currently playing, show
        // the pause/play icon overlay instead of the static badge.
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(accent),
        ) {
            when {
                isCurrent -> Icon(
                    imageVector = if (isPlaying) Icons.Outlined.Pause else Icons.Outlined.PlayArrow,
                    contentDescription = if (isPlaying) "Pausar" else "Reproducir",
                    tint = Color.White,
                )
                track.hz != null -> Text(
                    text = "${track.hz}",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                )
                else -> Icon(
                    imageVector = Icons.Outlined.PlayCircleOutline,
                    contentDescription = null,
                    tint = Color.White,
                )
            }
        }
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 12.dp),
        ) {
            Text(
                text = track.displayName,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = if (isCurrent) accent else MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
            )
            Text(
                text = track.displayDesc,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
            )
        }
        Text(
            text = track.durationLabel,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
