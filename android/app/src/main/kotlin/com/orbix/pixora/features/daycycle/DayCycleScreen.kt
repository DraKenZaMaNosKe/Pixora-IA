package com.orbix.pixora.features.daycycle

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.theme.PixoraColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import com.orbix.pixora.data.models.DayCycleTheme
import com.orbix.pixora.data.repos.DayCycleRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DayCycleUiState(
    val themes: List<DayCycleTheme> = emptyList(),
    val loading: Boolean = true,
    val errorMsg: String? = null,
)

@HiltViewModel
class DayCycleViewModel @Inject constructor(
    private val repo: DayCycleRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(DayCycleUiState())
    val state: StateFlow<DayCycleUiState> = _state.asStateFlow()
    init { refresh() }
    fun refresh() = viewModelScope.launch {
        val list = repo.fetchAll()
        _state.value = DayCycleUiState(
            themes = list,
            loading = false,
            errorMsg = if (list.isEmpty()) "Sin temas Day Cycle todavía" else null,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DayCycleScreen(
    onThemeClick: (String) -> Unit = {},
    viewModel: DayCycleViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    Scaffold(
        containerColor = PixoraColors.Ink,
        topBar = {
            PixoraAppBar(
                title = "Day Cycle",
                eyebrow = "// ALMANAC · CYCLES",
                subtitle = if (state.themes.isEmpty()) null
                    else "${state.themes.size} temas que siguen al sol",
                accentColor = PixoraColors.AuroraOcean,
            )
        },
    ) { innerPadding ->
        Box(Modifier.fillMaxSize().padding(innerPadding)) {
            when {
                state.loading && state.themes.isEmpty() -> CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.errorMsg != null && state.themes.isEmpty() -> Text(
                    text = state.errorMsg!!,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> ThemesGrid(state.themes, onThemeClick)
            }
        }
    }
}

@Composable
private fun ThemesGrid(themes: List<DayCycleTheme>, onClick: (String) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(themes, key = { it.id }) { theme -> ThemeCard(theme) { onClick(theme.id) } }
    }
}

@Composable
private fun ThemeCard(theme: DayCycleTheme, onClick: () -> Unit) {
    val context = LocalContext.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable { onClick() },
    ) {
        // 2x2 mosaic of the 4 day periods
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(9f / 16f),
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().weight(1f)) {
                    MosaicCell(context, theme.morningUrl, Modifier.weight(1f).fillMaxHeight(), "Mañana")
                    MosaicCell(context, theme.afternoonUrl, Modifier.weight(1f).fillMaxHeight(), "Tarde")
                }
                Row(Modifier.fillMaxWidth().weight(1f)) {
                    MosaicCell(context, theme.eveningUrl, Modifier.weight(1f).fillMaxHeight(), "Atardecer")
                    MosaicCell(context, theme.nightUrl, Modifier.weight(1f).fillMaxHeight(), "Noche")
                }
            }
        }
        Column(Modifier.padding(8.dp)) {
            Text(
                text = theme.name,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
            )
            Text(
                text = "4 escenas",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun MosaicCell(
    context: android.content.Context,
    url: String,
    modifier: Modifier,
    label: String,
) {
    Box(modifier) {
        AsyncImage(
            model = ImageRequest.Builder(context).data(url).crossfade(true).build(),
            contentDescription = label,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = Color.White,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(4.dp),
        )
    }
}
