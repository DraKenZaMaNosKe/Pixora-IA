package com.orbix.pixora.features.ringtones

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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.theme.PixoraColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.orbix.pixora.data.models.Ringtone
import com.orbix.pixora.data.models.RingtonePack
import com.orbix.pixora.data.repos.RingtoneRepository
import com.orbix.pixora.data.ringtones.RingtonePreviewPlayer
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class RingtonesUiState(
    val packs: List<RingtonePack> = emptyList(),
    val loading: Boolean = true,
    val errorMsg: String? = null,
)

@HiltViewModel
class RingtonesViewModel @Inject constructor(
    private val repo: RingtoneRepository,
    private val previewPlayer: RingtonePreviewPlayer,
) : ViewModel() {
    private val _state = MutableStateFlow(RingtonesUiState())
    val state: StateFlow<RingtonesUiState> = _state.asStateFlow()
    val nowPlayingId: StateFlow<String?> = previewPlayer.nowPlayingId

    init { refresh() }
    fun refresh() = viewModelScope.launch {
        val list = repo.fetchAll()
        _state.value = RingtonesUiState(
            packs = list,
            loading = false,
            errorMsg = if (list.isEmpty()) "Sin packs de tonos todavía" else null,
        )
    }

    fun onToneTapped(tone: Ringtone) = previewPlayer.toggle(tone.id, tone.audioUrl)

    override fun onCleared() {
        previewPlayer.stop()
        super.onCleared()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RingtonesScreen(viewModel: RingtonesViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val nowPlayingId by viewModel.nowPlayingId.collectAsStateWithLifecycle()
    Scaffold(
        containerColor = PixoraColors.Ink,
        topBar = {
            PixoraAppBar(
                title = "Tonos",
                eyebrow = "// RETRO · CASSETTE",
                subtitle = if (state.packs.isEmpty()) null
                    else "${state.packs.size} packs · ringtones + notificaciones",
                accentColor = PixoraColors.AuroraMagenta,
            )
        },
    ) { innerPadding ->
        Box(Modifier.fillMaxSize().padding(innerPadding)) {
            when {
                state.loading && state.packs.isEmpty() -> CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.errorMsg != null && state.packs.isEmpty() -> Text(
                    text = state.errorMsg!!,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> PacksList(state.packs, nowPlayingId, viewModel::onToneTapped)
            }
        }
    }
}

@Composable
private fun PacksList(
    packs: List<RingtonePack>,
    nowPlayingId: String?,
    onToneTap: (Ringtone) -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(packs, key = { it.id }) { pack -> PackCard(pack, nowPlayingId, onToneTap) }
    }
}

@Composable
private fun PackCard(
    pack: RingtonePack,
    nowPlayingId: String?,
    onToneTap: (Ringtone) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val context = LocalContext.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(12.dp),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(context).data(pack.previewUrl).crossfade(true).build(),
                contentDescription = pack.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.surface),
            )
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 12.dp),
            ) {
                Text(
                    text = pack.name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "${pack.tones.size} tonos · ${pack.category}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (expanded) {
            Column(modifier = Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp)) {
                pack.tones.forEach { tone ->
                    ToneRow(
                        tone = tone,
                        isPlaying = tone.id == nowPlayingId,
                        onTap = { onToneTap(tone) },
                    )
                }
            }
        }
    }
}

@Composable
private fun ToneRow(tone: Ringtone, isPlaying: Boolean, onTap: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onTap() }
            .padding(vertical = 6.dp),
    ) {
        Icon(
            imageVector = if (isPlaying) Icons.Outlined.StopCircle else Icons.Outlined.PlayCircle,
            contentDescription = if (isPlaying) "Detener" else "Reproducir",
            tint = if (isPlaying) Color(0xFFE53935) else MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(28.dp),
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp),
        ) {
            Text(
                text = tone.name,
                style = MaterialTheme.typography.bodyMedium,
                color = if (isPlaying) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurface,
                fontWeight = if (isPlaying) FontWeight.SemiBold else FontWeight.Normal,
                maxLines = 1,
            )
            Text(
                text = tone.suggestedType,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(
            text = "${tone.duration}s",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
