package com.orbix.pixora.features.daycycle

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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
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
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalTime
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
                eyebrow = "// HOUR SLIDER · TIME SCRUBBER",
                subtitle = if (state.themes.isEmpty()) null
                    else "${state.themes.size} temas que siguen al sol",
                accentColor = PixoraColors.AuroraOcean,
            )
        },
    ) { innerPadding ->
        Box(Modifier.fillMaxSize().padding(innerPadding)) {
            when {
                state.loading && state.themes.isEmpty() -> CircularProgressIndicator(
                    color = PixoraColors.AuroraOcean,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.errorMsg != null && state.themes.isEmpty() -> Text(
                    text = state.errorMsg!!,
                    style = MaterialTheme.typography.bodyMedium.copy(color = PixoraColors.TextSecondary),
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> ThemesWithSlider(state.themes, onThemeClick)
            }
        }
    }
}

@Composable
private fun ThemesWithSlider(themes: List<DayCycleTheme>, onClick: (String) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            HourSliderHero()
        }
        items(themes, key = { it.id }) { theme ->
            ThemeMosaicCard(theme) { onClick(theme.id) }
        }
    }
}

@Composable
private fun HourSliderHero() {
    // Track current hour every minute so the marker drifts
    var now by remember { mutableStateOf(LocalTime.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000)
            now = LocalTime.now()
        }
    }
    val hour = now.hour
    val minute = now.minute
    val fractional = (hour + minute / 60f).coerceIn(0f, 24f)
    val period = currentPeriod(hour)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 6.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(PixoraColors.Surface)
            .border(
                width = 0.7.dp,
                color = PixoraColors.AuroraOcean.copy(alpha = 0.35f),
                shape = RoundedCornerShape(14.dp),
            )
            .padding(14.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = "AHORA · ${period.name}",
                style = MaterialTheme.typography.labelMedium.copy(
                    color = period.accent,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
            Text(
                text = "%02d:%02d".format(hour, minute),
                style = MaterialTheme.typography.labelMedium.copy(
                    color = PixoraColors.GoldBright,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
        }
        Spacer(Modifier.height(2.dp))
        Text(
            text = period.label,
            style = MaterialTheme.typography.displaySmall.copy(
                color = PixoraColors.TextPrimary,
                fontFamily = PixoraFonts.Fraunces,
                fontStyle = FontStyle.Italic,
                fontWeight = FontWeight.W400,
            ),
        )
        Spacer(Modifier.height(14.dp))
        TimelineCanvas(fractional)
        Spacer(Modifier.height(8.dp))
        HourTicks()
    }
}

private data class Period(val name: String, val label: String, val accent: Color)

private fun currentPeriod(hour: Int): Period = when (hour) {
    in 6..11 -> Period("AURORA", "Mañana fresca", PixoraColors.AuroraPeach)
    in 12..17 -> Period("MERIDIANO", "Tarde dorada", PixoraColors.GoldBright)
    in 18..20 -> Period("CREPÚSCULO", "Atardecer cálido", PixoraColors.AuroraMagenta)
    else -> Period("NOCTURNO", "Noche profunda", PixoraColors.AuroraLavender)
}

@Composable
private fun TimelineCanvas(fractionalHour: Float) {
    val ratio = (fractionalHour / 24f).coerceIn(0f, 1f)
    val dawn = PixoraColors.AuroraPeach
    val noon = PixoraColors.GoldBright
    val dusk = PixoraColors.AuroraMagenta
    val night = PixoraColors.AuroraViolet

    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(36.dp),
    ) {
        val barH = 12f
        val cy = size.height / 2f
        // Backing gradient bar
        drawRoundRect(
            brush = Brush.horizontalGradient(
                0f to night.copy(alpha = 0.7f),     // 0:00
                0.25f to dawn.copy(alpha = 0.85f),  // 6:00
                0.5f to noon.copy(alpha = 0.95f),   // 12:00
                0.75f to dusk.copy(alpha = 0.9f),   // 18:00
                1f to night.copy(alpha = 0.7f),     // 24:00
            ),
            topLeft = Offset(0f, cy - barH / 2),
            size = androidx.compose.ui.geometry.Size(size.width, barH),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(barH / 2, barH / 2),
        )
        // Marker (sun/moon dot)
        val markerX = size.width * ratio
        drawCircle(
            color = Color.White,
            radius = 9f,
            center = Offset(markerX, cy),
        )
        drawCircle(
            color = PixoraColors.GoldBright,
            radius = 6f,
            center = Offset(markerX, cy),
        )
        drawCircle(
            color = Color.White,
            radius = 6f,
            center = Offset(markerX, cy),
            style = Stroke(width = 1.5f),
        )
    }
}

@Composable
private fun HourTicks() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        listOf("00", "06", "12", "18", "24").forEach { h ->
            Text(
                text = h,
                style = MaterialTheme.typography.labelSmall.copy(
                    color = PixoraColors.TextFaint,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W600,
                ),
            )
        }
    }
}

@Composable
private fun ThemeMosaicCard(theme: DayCycleTheme, onClick: () -> Unit) {
    val context = LocalContext.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(PixoraColors.Surface)
            .border(
                width = 0.5.dp,
                color = PixoraColors.AuroraOcean.copy(alpha = 0.3f),
                shape = RoundedCornerShape(12.dp),
            )
            .clickable { onClick() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(9f / 16f),
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().weight(1f)) {
                    PeriodCell(context, theme.morningUrl, Modifier.weight(1f).fillMaxHeight(), "AURORA")
                    PeriodCell(context, theme.afternoonUrl, Modifier.weight(1f).fillMaxHeight(), "MERIDIANO")
                }
                Row(Modifier.fillMaxWidth().weight(1f)) {
                    PeriodCell(context, theme.eveningUrl, Modifier.weight(1f).fillMaxHeight(), "CREPÚSCULO")
                    PeriodCell(context, theme.nightUrl, Modifier.weight(1f).fillMaxHeight(), "NOCTURNO")
                }
            }
        }
        Column(Modifier.padding(10.dp)) {
            Text(
                text = theme.name,
                style = MaterialTheme.typography.titleSmall.copy(
                    color = PixoraColors.TextPrimary,
                    fontFamily = PixoraFonts.Fraunces,
                    fontStyle = FontStyle.Italic,
                ),
                maxLines = 1,
            )
            Text(
                text = "// 4 ESCENAS",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = PixoraColors.AuroraOcean,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W600,
                ),
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}

@Composable
private fun PeriodCell(
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
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(4.dp)
                .clip(CircleShape)
                .background(Color(0xAA000000))
                .padding(horizontal = 5.dp, vertical = 1.dp),
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall.copy(
                    color = PixoraColors.GoldBright,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
        }
    }
}
