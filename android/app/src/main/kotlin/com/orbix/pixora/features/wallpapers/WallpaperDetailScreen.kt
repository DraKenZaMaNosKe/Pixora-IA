package com.orbix.pixora.features.wallpapers

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.width
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.orbix.pixora.data.wallpaper.ApplyTarget
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
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.orbix.pixora.ui.components.DownloadManagerOverlay
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts

/**
 * Static wallpaper detail — opens when tapping a card in the grid.
 *
 * Trading Card vibe but full-bleed: image fills the screen, top scrim
 * hosts back button + Fraunces italic title with gold first word,
 * bottom scrim hosts the Apply CTA. Aura HUD (cards swipeable) is a
 * SEPARATE flow triggered by tapping chips, not cards — see
 * WallpaperExplorerHud for that.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WallpaperDetailScreen(
    @Suppress("UNUSED_PARAMETER") wallpaperId: String,
    onBack: () -> Unit,
    viewModel: WallpaperDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val snackHost = remember { SnackbarHostState() }
    val context = LocalContext.current
    val activity = context as? Activity
    var showTargetSheet by remember { mutableStateOf(false) }

    LaunchedEffect(state.event) {
        when (val e = state.event) {
            is DetailEvent.Toast -> {
                snackHost.showSnackbar(e.message)
                viewModel.consumeEvent()
            }
            null -> Unit
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackHost) },
        containerColor = PixoraColors.Ink,
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                state.loading -> CircularProgressIndicator(
                    color = PixoraColors.GoldBright,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.wallpaper == null -> Text(
                    text = state.errorMsg ?: "Sin datos",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> DetailContent(
                    state = state,
                    onBack = onBack,
                    onApply = { showTargetSheet = true },
                    context = context,
                )
            }
            DownloadManagerOverlay(
                stage = state.downloadStage,
                errorMessage = state.downloadError,
            )
        }
    }

    if (showTargetSheet) {
        ApplyTargetSheet(
            isPanoramic = state.wallpaper?.isPanoramic == true,
            onPick = { target ->
                showTargetSheet = false
                activity?.let { viewModel.apply(it, target) }
            },
            onDismiss = { showTargetSheet = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ApplyTargetSheet(
    isPanoramic: Boolean,
    onPick: (ApplyTarget) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = PixoraColors.Ink2,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = "// APLICAR EN",
                style = MaterialTheme.typography.labelMedium.copy(
                    color = PixoraColors.GoldBright,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
            Text(
                text = if (isPanoramic) "Para que el scroll panorámico funcione, escoge solo Pantalla principal"
                       else "¿Dónde quieres aplicar este wallpaper?",
                style = MaterialTheme.typography.bodyMedium.copy(color = PixoraColors.TextSecondary),
                modifier = Modifier.padding(bottom = 8.dp),
            )
            TargetOption(
                title = "Pantalla principal",
                subtitle = if (isPanoramic) "Recomendado para panorámicos · scroll horizontal nativo" else "Solo el home",
                recommended = isPanoramic,
                onClick = { onPick(ApplyTarget.Home) },
            )
            TargetOption(
                title = "Pantalla de bloqueo",
                subtitle = "Solo el lockscreen",
                recommended = false,
                onClick = { onPick(ApplyTarget.Lock) },
            )
            TargetOption(
                title = "Ambas pantallas",
                subtitle = if (isPanoramic) "El scroll panorámico puede no funcionar" else "Home + lockscreen",
                recommended = !isPanoramic,
                onClick = { onPick(ApplyTarget.Both) },
            )
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun TargetOption(
    title: String,
    subtitle: String,
    recommended: Boolean,
    onClick: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(vertical = 12.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall.copy(
                        color = PixoraColors.TextPrimary,
                        fontWeight = FontWeight.W700,
                    ),
                )
                if (recommended) {
                    Spacer(Modifier.width(8.dp))
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(PixoraColors.GoldBright)
                            .padding(horizontal = 6.dp, vertical = 1.dp),
                    ) {
                        Text(
                            text = "RECOMENDADO",
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
                text = subtitle,
                style = MaterialTheme.typography.labelSmall.copy(
                    color = PixoraColors.TextSecondary,
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
                modifier = Modifier.padding(top = 2.dp),
            )
        }
        Text(
            text = "›",
            style = MaterialTheme.typography.titleLarge.copy(color = PixoraColors.GoldBright),
        )
    }
}

@Composable
private fun DetailContent(
    state: WallpaperDetailUiState,
    onBack: () -> Unit,
    onApply: () -> Unit,
    context: android.content.Context,
) {
    val w = state.wallpaper ?: return
    val firstSpace = w.name.indexOf(' ')
    val firstWord = if (firstSpace > 0) w.name.substring(0, firstSpace) else w.name
    val restName = if (firstSpace > 0) w.name.substring(firstSpace) else ""

    Box(modifier = Modifier.fillMaxSize()) {
        AsyncImage(
            model = ImageRequest.Builder(context).data(w.imageUrl).crossfade(true).build(),
            contentDescription = w.name,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )

        // Top scrim
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(160.dp)
                .align(Alignment.TopCenter)
                .background(
                    Brush.verticalGradient(listOf(Color(0xCC000000), Color.Transparent)),
                ),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 8.dp, vertical = 4.dp),
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    imageVector = Icons.Outlined.ArrowBack,
                    contentDescription = "Volver",
                    tint = Color.White,
                )
            }
            // Eyebrow + title with gold first word
            Text(
                text = "// ADMIT · ONE",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = PixoraColors.GoldBright,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
                modifier = Modifier.padding(horizontal = 14.dp),
            )
            Spacer(Modifier.height(4.dp))
            Row(
                modifier = Modifier.padding(horizontal = 14.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(
                    text = firstWord,
                    style = MaterialTheme.typography.displayMedium.copy(
                        color = PixoraColors.GoldBright,
                        fontFamily = PixoraFonts.Fraunces,
                        fontStyle = FontStyle.Italic,
                    ),
                )
                if (restName.isNotEmpty()) {
                    Text(
                        text = restName,
                        style = MaterialTheme.typography.displayMedium.copy(
                            color = Color.White,
                            fontFamily = PixoraFonts.Fraunces,
                            fontStyle = FontStyle.Italic,
                        ),
                    )
                }
            }
            Text(
                text = w.authorName.uppercase(),
                style = MaterialTheme.typography.labelSmall.copy(
                    color = Color.White.copy(alpha = 0.7f),
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 4.dp),
            )
        }

        // Bottom scrim + Apply CTA
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
                .align(Alignment.BottomCenter)
                .background(
                    Brush.verticalGradient(listOf(Color.Transparent, Color(0xEE000000))),
                ),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomCenter)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Button(
                onClick = onApply,
                enabled = !state.applying && !state.justApplied,
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = when {
                        state.justApplied -> Color(0xFF10B981)
                        else -> PixoraColors.GoldBright
                    },
                    contentColor = PixoraColors.Ink,
                    disabledContainerColor = when {
                        state.justApplied -> Color(0xFF10B981)
                        else -> PixoraColors.GoldBright.copy(alpha = 0.5f)
                    },
                    disabledContentColor = PixoraColors.Ink,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
            ) {
                when {
                    state.applying -> {
                        CircularProgressIndicator(
                            color = PixoraColors.Ink,
                            strokeWidth = 2.dp,
                            modifier = Modifier.height(20.dp),
                        )
                        Spacer(Modifier.height(0.dp))
                        Text(
                            text = "  APLICANDO…",
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontFamily = PixoraFonts.JetBrainsMono,
                                fontWeight = FontWeight.W800,
                            ),
                        )
                    }
                    state.justApplied -> {
                        Icon(
                            imageVector = Icons.Outlined.CheckCircle,
                            contentDescription = null,
                            tint = PixoraColors.Ink,
                        )
                        Text(
                            text = "  WALLPAPER APLICADO",
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontFamily = PixoraFonts.JetBrainsMono,
                                fontWeight = FontWeight.W800,
                            ),
                        )
                    }
                    else -> Text(
                        text = "▶ APLICAR COMO WALLPAPER",
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontFamily = PixoraFonts.JetBrainsMono,
                            fontWeight = FontWeight.W800,
                        ),
                    )
                }
            }
        }
    }
}

