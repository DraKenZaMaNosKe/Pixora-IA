package com.orbix.pixora.features.stories

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Wallpaper
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.orbix.pixora.data.models.Story
import com.orbix.pixora.data.models.StoryFrame
import com.orbix.pixora.data.repos.StoryRepository
import com.orbix.pixora.data.wallpaper.ApplyResult
import com.orbix.pixora.data.wallpaper.WallpaperApplyService
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

data class StoryDetailUiState(
    val story: Story? = null,
    val loading: Boolean = true,
    val applying: Boolean = false,
    val toast: String? = null,
)

@HiltViewModel
class StoryDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: StoryRepository,
    private val applyService: WallpaperApplyService,
) : ViewModel() {

    private val storyId: String = savedStateHandle.get<String>("storyId").orEmpty()

    private val _state = MutableStateFlow(StoryDetailUiState())
    val state: StateFlow<StoryDetailUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val story = repo.fetchAll().firstOrNull { it.id == storyId }
            _state.value = StoryDetailUiState(story = story, loading = false)
        }
    }

    fun applyFrame(frameUrl: String) {
        if (_state.value.applying) return
        viewModelScope.launch {
            _state.value = _state.value.copy(applying = true)
            val result = applyService.applyFromUrl(frameUrl, isPanoramic = false)
            _state.value = _state.value.copy(
                applying = false,
                toast = when (result) {
                    is ApplyResult.Success -> "Frame aplicado ✨"
                    is ApplyResult.Error -> "Error: ${result.message}"
                    is ApplyResult.PickerLaunched -> null
                },
            )
        }
    }

    fun consumeToast() {
        _state.value = _state.value.copy(toast = null)
    }
}

/**
 * Marvel Splash Page viewer — swipeable story frames with caption
 * overlay. v1 had auto-rotate worker; v2 alpha keeps the manual
 * apply per frame.
 */
@Composable
fun StoryDetailScreen(
    @Suppress("UNUSED_PARAMETER") storyId: String,
    onBack: () -> Unit,
    viewModel: StoryDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val snackHost = remember { SnackbarHostState() }

    LaunchedEffect(state.toast) {
        val msg = state.toast ?: return@LaunchedEffect
        snackHost.showSnackbar(msg)
        viewModel.consumeToast()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackHost) },
        containerColor = Color.Black,
    ) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            when {
                state.loading -> CircularProgressIndicator(
                    color = ComicYellow,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.story == null -> Text(
                    text = "Historia no encontrada",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> SplashPager(
                    story = state.story!!,
                    applying = state.applying,
                    onBack = onBack,
                    onApplyFrame = viewModel::applyFrame,
                )
            }
        }
    }
}

@Composable
private fun SplashPager(
    story: Story,
    applying: Boolean,
    onBack: () -> Unit,
    onApplyFrame: (String) -> Unit,
) {
    val pagerState = rememberPagerState(initialPage = 0) { story.frames.size }
    val context = LocalContext.current

    Box(modifier = Modifier.fillMaxSize()) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize(),
        ) { page ->
            val frame: StoryFrame = story.frames[page]
            Box(modifier = Modifier.fillMaxSize()) {
                AsyncImage(
                    model = ImageRequest.Builder(context).data(frame.imageUrl).crossfade(true).build(),
                    contentDescription = "Frame ${page + 1}",
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
                // Bottom gradient + caption
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(260.dp)
                        .align(Alignment.BottomCenter)
                        .background(
                            Brush.verticalGradient(
                                listOf(Color.Transparent, Color(0xEE000000)),
                            ),
                        ),
                )
                if (frame.captionEs.isNotBlank()) {
                    Text(
                        text = frame.captionEs,
                        style = MaterialTheme.typography.titleSmall.copy(
                            color = Color.White,
                            fontWeight = FontWeight.W700,
                        ),
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .windowInsetsPadding(WindowInsets.navigationBars)
                            .padding(horizontal = 20.dp, vertical = 80.dp),
                    )
                }
            }
        }

        // Top bar: back + title + frame count
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 12.dp, vertical = 8.dp),
        ) {
            IconButton(onClick = onBack)
            Text(
                text = story.title.uppercase(),
                style = MaterialTheme.typography.labelMedium.copy(
                    color = ComicYellow,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W800,
                ),
                maxLines = 1,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
            FrameCountBadge(
                current = pagerState.currentPage + 1,
                total = story.frames.size,
            )
        }

        // Apply current frame as wallpaper (bottom-right floating)
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(20.dp)
                .size(56.dp)
                .clip(CircleShape)
                .background(ComicRed)
                .border(2.dp, ComicYellow, CircleShape)
                .clickable(enabled = !applying) {
                    onApplyFrame(story.frames[pagerState.currentPage].imageUrl)
                },
        ) {
            if (applying) {
                CircularProgressIndicator(
                    color = Color.White,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(20.dp),
                )
            } else {
                Icon(
                    imageVector = Icons.Outlined.Wallpaper,
                    contentDescription = "Aplicar frame",
                    tint = Color.White,
                    modifier = Modifier.size(24.dp),
                )
            }
        }

        // Frame dots indicator (top-center under status bar)
        FrameDots(
            count = story.frames.size,
            current = pagerState.currentPage,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(top = 56.dp),
        )
    }
}

@Composable
private fun IconButton(onClick: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(Color(0xAA000000))
            .clickable { onClick() },
    ) {
        Icon(
            imageVector = Icons.Outlined.ArrowBack,
            contentDescription = "Volver",
            tint = Color.White,
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
private fun FrameCountBadge(current: Int, total: Int) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(ComicYellow)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    ) {
        Text(
            text = "CAP. ${"%02d".format(current)} / ${"%02d".format(total)}",
            style = MaterialTheme.typography.labelSmall.copy(
                color = Color.Black,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W900,
            ),
        )
    }
}

@Composable
private fun FrameDots(count: Int, current: Int, modifier: Modifier = Modifier) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = modifier,
    ) {
        repeat(count) { i ->
            val on = i == current
            Box(
                modifier = Modifier
                    .size(width = if (on) 18.dp else 6.dp, height = 6.dp)
                    .clip(RoundedCornerShape(50))
                    .background(if (on) ComicYellow else Color.White.copy(alpha = 0.4f)),
            )
        }
    }
}
