package com.orbix.pixora.features.daycycle

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowBack
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
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
import com.orbix.pixora.data.models.DayCycleTheme
import com.orbix.pixora.data.repos.DayCycleRepository
import com.orbix.pixora.data.wallpaper.ApplyResult
import com.orbix.pixora.data.wallpaper.WallpaperApplyService
import com.orbix.pixora.ui.components.DownloadManagerOverlay
import com.orbix.pixora.ui.components.DownloadStage
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

data class DayCycleDetailUiState(
    val theme: DayCycleTheme? = null,
    val loading: Boolean = true,
    val downloadStage: DownloadStage = DownloadStage.Idle,
    val downloadError: String? = null,
    val toast: String? = null,
)

@HiltViewModel
class DayCycleDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: DayCycleRepository,
    private val applyService: WallpaperApplyService,
) : ViewModel() {

    private val themeId: String = savedStateHandle.get<String>("themeId").orEmpty()

    private val _state = MutableStateFlow(DayCycleDetailUiState())
    val state: StateFlow<DayCycleDetailUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val theme = repo.fetchAll().firstOrNull { it.id == themeId }
            _state.value = DayCycleDetailUiState(theme = theme, loading = false)
        }
    }

    fun applyCurrentPeriod() {
        val theme = _state.value.theme ?: return
        if (_state.value.downloadStage != DownloadStage.Idle) return
        viewModelScope.launch {
            _state.value = _state.value.copy(downloadStage = DownloadStage.Downloading)
            val url = currentPeriodImageUrl(theme)
            delay(450)
            _state.value = _state.value.copy(downloadStage = DownloadStage.Applying)
            val result = applyService.applyFromUrl(url, isPanoramic = false)
            _state.value = _state.value.copy(
                downloadStage = if (result is ApplyResult.Success) DownloadStage.Success
                                else DownloadStage.Error,
                downloadError = (result as? ApplyResult.Error)?.message,
                toast = when (result) {
                    is ApplyResult.Success -> "Período actual aplicado ✨"
                    is ApplyResult.Error -> "Error: ${result.message}"
                    // Not reachable: DayCycle calls with isPanoramic=false.
                    is ApplyResult.PickerLaunched -> null
                },
            )
            delay(1500)
            _state.value = _state.value.copy(downloadStage = DownloadStage.Idle, downloadError = null)
        }
    }

    fun applySpecificPeriod(url: String) {
        if (_state.value.downloadStage != DownloadStage.Idle) return
        viewModelScope.launch {
            _state.value = _state.value.copy(downloadStage = DownloadStage.Applying)
            val result = applyService.applyFromUrl(url, isPanoramic = false)
            _state.value = _state.value.copy(
                downloadStage = if (result is ApplyResult.Success) DownloadStage.Success
                                else DownloadStage.Error,
                downloadError = (result as? ApplyResult.Error)?.message,
                toast = when (result) {
                    is ApplyResult.Success -> "Período aplicado ✨"
                    is ApplyResult.Error -> "Error: ${result.message}"
                    is ApplyResult.PickerLaunched -> null
                },
            )
            delay(1500)
            _state.value = _state.value.copy(downloadStage = DownloadStage.Idle, downloadError = null)
        }
    }

    fun consumeToast() {
        _state.value = _state.value.copy(toast = null)
    }
}

private data class PeriodEntry(val name: String, val label: String, val hours: String, val url: (DayCycleTheme) -> String)

private val Periods = listOf(
    PeriodEntry("AURORA", "Mañana fresca", "06:00 — 12:00") { it.morningUrl },
    PeriodEntry("MERIDIANO", "Tarde dorada", "12:00 — 18:00") { it.afternoonUrl },
    PeriodEntry("CREPÚSCULO", "Atardecer cálido", "18:00 — 21:00") { it.eveningUrl },
    PeriodEntry("NOCTURNO", "Noche profunda", "21:00 — 06:00") { it.nightUrl },
)

private fun currentPeriodImageUrl(theme: DayCycleTheme): String {
    val hour = LocalTime.now().hour
    return when (hour) {
        in 6..11 -> theme.morningUrl
        in 12..17 -> theme.afternoonUrl
        in 18..20 -> theme.eveningUrl
        else -> theme.nightUrl
    }
}

private fun currentPeriodIndex(): Int {
    val hour = LocalTime.now().hour
    return when (hour) {
        in 6..11 -> 0
        in 12..17 -> 1
        in 18..20 -> 2
        else -> 3
    }
}

@Composable
fun DayCycleDetailScreen(
    @Suppress("UNUSED_PARAMETER") themeId: String,
    onBack: () -> Unit,
    viewModel: DayCycleDetailViewModel = hiltViewModel(),
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
        containerColor = PixoraColors.Ink,
    ) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            when {
                state.loading -> CircularProgressIndicator(
                    color = PixoraColors.AuroraOcean,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.theme == null -> Text(
                    text = "Tema no encontrado",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> AlmanacContent(
                    theme = state.theme!!,
                    onBack = onBack,
                    onApplyCurrent = viewModel::applyCurrentPeriod,
                    onApplyPeriod = viewModel::applySpecificPeriod,
                )
            }
            DownloadManagerOverlay(
                stage = state.downloadStage,
                errorMessage = state.downloadError,
            )
        }
    }
}

@Composable
private fun AlmanacContent(
    theme: DayCycleTheme,
    onBack: () -> Unit,
    onApplyCurrent: () -> Unit,
    onApplyPeriod: (String) -> Unit,
) {
    val currentIdx = remember { currentPeriodIndex() }

    LazyColumn(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            // Header row: back + doc code
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(PixoraColors.Surface)
                        .border(0.5.dp, PixoraColors.Gold.copy(alpha = 0.4f), CircleShape)
                        .clickable { onBack() },
                ) {
                    Icon(
                        imageVector = Icons.Outlined.ArrowBack,
                        contentDescription = "Volver",
                        tint = PixoraColors.GoldBright,
                        modifier = Modifier.size(18.dp),
                    )
                }
                Spacer(Modifier.size(12.dp))
                Text(
                    text = "// ALMANAC · DOC-VII",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = PixoraColors.GoldDeep,
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W700,
                    ),
                )
            }
        }
        item {
            Text(
                text = theme.name,
                style = MaterialTheme.typography.displayMedium.copy(
                    color = PixoraColors.TextPrimary,
                    fontFamily = PixoraFonts.Fraunces,
                    fontStyle = FontStyle.Italic,
                    fontWeight = FontWeight.W400,
                ),
            )
            if (theme.description.isNotBlank()) {
                Text(
                    text = theme.description,
                    style = MaterialTheme.typography.bodyMedium.copy(
                        color = PixoraColors.TextSecondary,
                        fontFamily = PixoraFonts.CormorantItalic,
                        fontStyle = FontStyle.Italic,
                    ),
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        item {
            // Big "APLICAR PERÍODO ACTUAL" CTA
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(PixoraColors.GoldBright)
                    .clickable { onApplyCurrent() },
            ) {
                Text(
                    text = "▶ APLICAR PERÍODO ACTUAL · ${Periods[currentIdx].name}",
                    style = MaterialTheme.typography.titleSmall.copy(
                        color = PixoraColors.Ink,
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W800,
                    ),
                )
            }
        }
        item {
            Text(
                text = "ENTRADAS DEL ALMANAQUE",
                style = MaterialTheme.typography.labelMedium.copy(
                    color = PixoraColors.GoldBright,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        items(count = Periods.size) { i ->
            val period = Periods[i]
            AlmanacEntry(
                period = period,
                theme = theme,
                isNow = i == currentIdx,
                roman = listOf("I", "II", "III", "IV")[i],
                onApply = { onApplyPeriod(period.url(theme)) },
            )
        }
    }
}

@Composable
private fun AlmanacEntry(
    period: PeriodEntry,
    theme: DayCycleTheme,
    isNow: Boolean,
    roman: String,
    onApply: () -> Unit,
) {
    val context = LocalContext.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(PixoraColors.Surface)
            .border(
                width = if (isNow) 1.dp else 0.5.dp,
                color = if (isNow) PixoraColors.GoldBright else PixoraColors.AuroraOcean.copy(alpha = 0.25f),
                shape = RoundedCornerShape(12.dp),
            )
            .clickable { onApply() }
            .padding(8.dp),
    ) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .clip(RoundedCornerShape(10.dp)),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(context).data(period.url(theme)).crossfade(true).build(),
                contentDescription = period.label,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "CAPÍTULO $roman · ${period.name}",
                    style = MaterialTheme.typography.labelMedium.copy(
                        color = if (isNow) PixoraColors.GoldBright else PixoraColors.AuroraOcean,
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W700,
                    ),
                )
                if (isNow) {
                    Spacer(Modifier.size(8.dp))
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(PixoraColors.GoldBright)
                            .padding(horizontal = 6.dp, vertical = 1.dp),
                    ) {
                        Text(
                            text = "NOW",
                            style = MaterialTheme.typography.labelSmall.copy(
                                color = PixoraColors.Ink,
                                fontFamily = PixoraFonts.JetBrainsMono,
                                fontWeight = FontWeight.W900,
                            ),
                        )
                    }
                }
            }
            Text(
                text = period.label,
                style = MaterialTheme.typography.titleSmall.copy(
                    color = PixoraColors.TextPrimary,
                    fontFamily = PixoraFonts.Fraunces,
                    fontStyle = FontStyle.Italic,
                ),
            )
            Text(
                text = period.hours,
                style = MaterialTheme.typography.labelSmall.copy(
                    color = PixoraColors.TextFaint,
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
            )
        }
        Text(
            text = "›",
            style = MaterialTheme.typography.titleLarge.copy(
                color = PixoraColors.GoldBright,
            ),
            modifier = Modifier.padding(end = 8.dp),
        )
    }
}
