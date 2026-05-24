package com.orbix.pixora.features.stories

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
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
import com.orbix.pixora.data.models.Story
import com.orbix.pixora.data.repos.StoryRepository
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

private val ComicYellow = Color(0xFFFFD66B)
private val ComicRed = Color(0xFFFF2D7A)
private val ComicInk = Color(0xFF0F0E1A)

data class StoriesUiState(
    val stories: List<Story> = emptyList(),
    val loading: Boolean = true,
    val errorMsg: String? = null,
)

@HiltViewModel
class StoriesViewModel @Inject constructor(
    private val repo: StoryRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(StoriesUiState())
    val state: StateFlow<StoriesUiState> = _state.asStateFlow()
    init { refresh() }
    fun refresh() = viewModelScope.launch {
        val list = repo.fetchAll()
        _state.value = StoriesUiState(
            stories = list,
            loading = false,
            errorMsg = if (list.isEmpty()) "Sin historias publicadas todavía" else null,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoriesScreen(
    onStoryClick: (String) -> Unit = {},
    viewModel: StoriesViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    Scaffold(
        containerColor = PixoraColors.Ink,
        topBar = {
            PixoraAppBar(
                title = "Historias",
                eyebrow = "// COMIC BOOK · CHRONICLES",
                subtitle = if (state.stories.isEmpty()) null
                    else "${state.stories.size} sagas en movimiento — ¡KAPOW!",
                accentColor = ComicRed,
            )
        },
    ) { innerPadding ->
        Box(Modifier.fillMaxSize().padding(innerPadding)) {
            when {
                state.loading && state.stories.isEmpty() -> CircularProgressIndicator(
                    color = ComicYellow,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.errorMsg != null && state.stories.isEmpty() -> Text(
                    text = state.errorMsg!!,
                    style = MaterialTheme.typography.bodyMedium.copy(color = PixoraColors.TextSecondary),
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> StoriesGrid(state.stories, onStoryClick)
            }
        }
    }
}

@Composable
private fun StoriesGrid(stories: List<Story>, onClick: (String) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(stories, key = { it.id }) { story -> ComicPanel(story) { onClick(story.id) } }
    }
}

/**
 * Comic Book Panel card. Aesthetic:
 *  - Yellow ink frame + thick black border (newsprint pulp)
 *  - Halftone dot pattern overlay on cover (Roy Lichtenstein)
 *  - "CAP. N" badge top-right pasted on rotated -3°
 *  - Title in Geist W900 with comic-stroke shadow
 *  - Onomatopoeya speech bubble (¡KAPOW! / ¡BAM! random) bottom-left
 */
@Composable
private fun ComicPanel(story: Story, onClick: () -> Unit) {
    val context = LocalContext.current
    val sfx = remember(story.id) {
        listOf("¡KAPOW!", "¡BAM!", "¡BOOM!", "¡ZAP!", "¡POW!", "¡COSMO!").random()
    }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .aspectRatio(9f / 16f)
            .clip(RoundedCornerShape(12.dp))
            .background(ComicInk)
            .border(
                width = 2.dp,
                color = ComicYellow,
                shape = RoundedCornerShape(12.dp),
            )
            .clickable { onClick() },
    ) {
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(story.coverUrl)
                .crossfade(true)
                .build(),
            contentDescription = story.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        // Halftone dot overlay — fixed dot grid drawn over the image
        HalftoneOverlay()
        // Bottom gradient + title
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(130.dp)
                .align(Alignment.BottomCenter)
                .background(
                    Brush.verticalGradient(listOf(Color.Transparent, Color(0xEE000000))),
                ),
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(10.dp),
        ) {
            Text(
                text = story.title,
                style = MaterialTheme.typography.titleSmall.copy(
                    color = Color.White,
                    fontWeight = FontWeight.W900,
                ),
                maxLines = 2,
            )
            Spacer(Modifier.height(2.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "${story.frames.size} CAPÍTULOS",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = ComicYellow,
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W700,
                    ),
                )
                Text(
                    text = "·",
                    style = MaterialTheme.typography.labelSmall.copy(color = ComicYellow),
                )
                Text(
                    text = "${story.intervalMinutes} MIN",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = ComicYellow,
                        fontFamily = PixoraFonts.JetBrainsMono,
                    ),
                )
            }
        }
        // CAP. 01 badge top-left
        Box(
            modifier = Modifier
                .padding(6.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(ComicYellow)
                .padding(horizontal = 6.dp, vertical = 2.dp),
        ) {
            Text(
                text = "CAP. 01",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = ComicInk,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W900,
                ),
            )
        }
        // Onomatopoeya speech bubble top-right (rotated subtly)
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 22.dp, end = 8.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(ComicRed)
                .border(1.dp, Color.White, RoundedCornerShape(4.dp))
                .padding(horizontal = 8.dp, vertical = 3.dp),
        ) {
            Text(
                text = sfx,
                style = MaterialTheme.typography.labelMedium.copy(
                    color = Color.White,
                    fontWeight = FontWeight.W900,
                ),
            )
        }
    }
}

/**
 * Halftone dot grid drawn over the image with low alpha — gives the
 * classic newsprint comic look without needing a PNG asset.
 */
@Composable
private fun HalftoneOverlay() {
    Canvas(modifier = Modifier.fillMaxSize()) {
        val step = 8f
        val r = 1.2f
        var y = 0f
        while (y < size.height) {
            var x = if ((y / step).toInt() % 2 == 0) 0f else step / 2
            while (x < size.width) {
                drawCircle(
                    color = Color.Black.copy(alpha = 0.18f),
                    radius = r,
                    center = Offset(x, y),
                )
                x += step
            }
            y += step
        }
    }
}
