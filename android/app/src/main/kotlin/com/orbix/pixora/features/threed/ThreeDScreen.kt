package com.orbix.pixora.features.threed

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.models.Wallpaper
import com.orbix.pixora.data.repos.WallpaperRepository
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.components.TiltImage
import com.orbix.pixora.ui.components.rememberTiltState
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ThreeDUiState(
    val items: List<Wallpaper> = emptyList(),
    val loading: Boolean = true,
)

@HiltViewModel
class ThreeDViewModel @Inject constructor(
    private val repo: WallpaperRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(ThreeDUiState())
    val state: StateFlow<ThreeDUiState> = _state.asStateFlow()

    /** Categories that look great with tilt parallax (depth, characters, scenes). */
    private val tiltCategories = setOf("ANIME", "SCIFI", "FANTASY", "SCENES", "UNIVERSE", "GAMING")

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val all = repo.fetchAll()
            val curated = all.filter {
                it.category.uppercase() in tiltCategories || it.featured
            }
            _state.value = ThreeDUiState(items = curated, loading = false)
        }
    }
}

/**
 * 3D · TILT — curated wallpapers with gyroscope parallax preview.
 *
 * v1's "3D" was an apply mode that gyro-shifted any wallpaper. v2
 * captures it as a section that curates depth-friendly artwork
 * (anime characters with backgrounds, sci-fi scenes, fantasy
 * landscapes) and previews them with the tilt effect inline.
 *
 * Single SensorEventListener at screen level (via rememberTiltState)
 * feeds all visible cards.
 */
@Composable
fun ThreeDScreen(
    onWallpaperClick: (String) -> Unit = {},
    viewModel: ThreeDViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val tilt = rememberTiltState()

    Scaffold(
        containerColor = PixoraColors.Ink,
        topBar = {
            PixoraAppBar(
                title = "3D · Tilt",
                eyebrow = "// HOLOGRAPHIC · TILT",
                subtitle = if (state.items.isEmpty()) null
                    else "Mueve tu celular — la imagen sigue tu mano",
                accentColor = PixoraColors.AuroraCyan,
            )
        },
    ) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            when {
                state.loading && state.items.isEmpty() -> CircularProgressIndicator(
                    color = PixoraColors.AuroraCyan,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.items.isEmpty() -> Text(
                    text = "Sin piezas 3D todavía",
                    style = MaterialTheme.typography.bodyMedium.copy(color = PixoraColors.TextSecondary),
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> TiltGrid(
                    items = state.items,
                    onCardTap = onWallpaperClick,
                    rollState = tilt.roll.value,
                    pitchState = tilt.pitch.value,
                    tiltState = tilt,
                )
            }
        }
    }
}

@Composable
private fun TiltGrid(
    items: List<Wallpaper>,
    onCardTap: (String) -> Unit,
    rollState: Float,
    pitchState: Float,
    tiltState: com.orbix.pixora.ui.components.TiltState,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        items(items, key = { it.id }) { w -> TiltCard(w, tiltState, onCardTap) }
    }
}

@Composable
private fun TiltCard(
    wallpaper: Wallpaper,
    tilt: com.orbix.pixora.ui.components.TiltState,
    onTap: (String) -> Unit,
) {
    val glow = runCatching { Color(android.graphics.Color.parseColor(wallpaper.glowColor)) }
        .getOrDefault(PixoraColors.AuroraCyan)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(9f / 16f)
            .clip(RoundedCornerShape(14.dp))
            .border(
                width = 1.dp,
                brush = Brush.verticalGradient(
                    listOf(glow.copy(alpha = 0.7f), glow.copy(alpha = 0.1f)),
                ),
                shape = RoundedCornerShape(14.dp),
            )
            .background(PixoraColors.Surface)
            .clickable { onTap(wallpaper.id) },
    ) {
        TiltImage(
            url = wallpaper.previewUrl,
            contentDescription = wallpaper.name,
            tilt = tilt,
            modifier = Modifier.fillMaxSize(),
            maxShiftPx = 32f,
            extraZoom = 1.18f,
        )
        // Bottom scrim + title
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp)
                .align(Alignment.BottomCenter)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color(0xEE000000)),
                    ),
                ),
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(10.dp),
        ) {
            Text(
                text = wallpaper.name,
                style = MaterialTheme.typography.titleSmall.copy(
                    color = Color.White,
                    fontFamily = PixoraFonts.Fraunces,
                    fontStyle = FontStyle.Italic,
                    fontWeight = FontWeight.W500,
                ),
                maxLines = 2,
            )
            Spacer(Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "3D",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = glow,
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W900,
                    ),
                    modifier = Modifier
                        .clip(RoundedCornerShape(3.dp))
                        .background(Color(0xAA000000))
                        .padding(horizontal = 5.dp, vertical = 1.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = "TILT · " + wallpaper.category.uppercase(),
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = Color.White.copy(alpha = 0.7f),
                        fontFamily = PixoraFonts.JetBrainsMono,
                    ),
                )
            }
        }
    }
}
