package com.orbix.pixora.features.live

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowBack
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import android.app.Activity
import com.orbix.pixora.data.models.LiveWallpaper
import com.orbix.pixora.ui.components.DownloadManagerOverlay
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts
import kotlinx.coroutines.launch

/**
 * Live wallpaper detail — Frosted Stage (concept #5 from
 * live_preview_page_concepts.html).
 *
 * Video full-bleed background (Media3 ExoPlayer with looping + muted),
 * frosted glass panels floating over the video:
 *  - glass-top: ‹ back button + CATEGORY pill + LIVE red badge
 *  - title-block: name in Fraunces italic (warm gold dark theme)
 *  - stats-glass: 3 chips (LIKES / VIEWS / DL)
 *  - apply-glass: big breathing gold gradient APPLY WALLPAPER CTA
 *  - floats: 3 small action squares (↓ ♡ ↗)
 *
 * Apply flow for live wallpapers is stubbed — needs PixoraWallpaperService
 * port from the legacy Flutter code. For now tapping APPLY shows a toast.
 */
@Composable
fun LiveDetailScreen(
    @Suppress("UNUSED_PARAMETER") wallpaperId: String,
    onBack: () -> Unit,
    viewModel: LiveDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val snackHost = remember { SnackbarHostState() }
    val activity = LocalContext.current as? Activity

    LaunchedEffect(state.toast) {
        val msg = state.toast ?: return@LaunchedEffect
        snackHost.showSnackbar(msg)
        viewModel.consumeToast()
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
                else -> FrostedStage(
                    wallpaper = state.wallpaper!!,
                    onBack = onBack,
                    onApply = { activity?.let { viewModel.apply(it) } },
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
private fun FrostedStage(
    wallpaper: LiveWallpaper,
    onBack: () -> Unit,
    onApply: () -> Unit,
) {
    Box(modifier = Modifier.fillMaxSize()) {
        // Background: looping muted video
        LoopingVideo(
            url = wallpaper.videoUrl,
            modifier = Modifier.fillMaxSize(),
        )

        // Vignette top/bottom for glass legibility
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color(0x33000000),
                            Color.Transparent,
                            Color.Transparent,
                            Color(0xAA000000),
                        ),
                        startY = 0f,
                    ),
                ),
        )

        // Glass top bar
        GlassTopBar(
            category = wallpaper.category,
            onBack = onBack,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 12.dp, vertical = 8.dp),
        )

        // Bottom block: title + stats + apply + action floats
        Column(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(16.dp),
        ) {
            TitleBlock(name = wallpaper.name)
            StatsGlass(wallpaper)
            ApplyGlass(onClick = onApply)
            ActionFloats(
                onDownload = { /* TODO Phase 3 */ },
                onFavorite = { /* TODO Phase 3 */ },
                onShare = { /* TODO Phase 3 */ },
            )
        }
    }
}

@Composable
private fun LoopingVideo(url: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val player = remember {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(url))
            repeatMode = Player.REPEAT_MODE_ONE
            volume = 0f
            prepare()
            playWhenReady = true
        }
    }
    DisposableEffect(Unit) {
        onDispose { player.release() }
    }
    AndroidView(
        factory = {
            PlayerView(it).apply {
                this.player = player
                useController = false
                resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            }
        },
        modifier = modifier,
    )
}

@Composable
private fun GlassTopBar(
    category: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0x73141420))
            .border(
                width = 0.5.dp,
                color = PixoraColors.Gold.copy(alpha = 0.3f),
                shape = RoundedCornerShape(14.dp),
            )
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Icon(
            imageVector = Icons.Outlined.ArrowBack,
            contentDescription = "Volver",
            tint = PixoraColors.TextPrimary,
            modifier = Modifier
                .size(20.dp)
                .clickable { onBack() },
        )
        Text(
            text = "‹ $category".uppercase(),
            style = MaterialTheme.typography.labelSmall.copy(
                color = PixoraColors.GoldBright,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
            modifier = Modifier.weight(1f),
        )
        LiveBadge()
    }
}

@Composable
private fun LiveBadge() {
    val infinite = rememberInfiniteTransition(label = "live")
    val pulse by infinite.animateFloat(
        initialValue = 0.6f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "livePulse",
    )
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Color(0xFFFF3B30).copy(alpha = 0.25f))
            .border(
                width = 0.6.dp,
                color = Color(0xFFFF3B30).copy(alpha = pulse),
                shape = RoundedCornerShape(50),
            )
            .padding(horizontal = 8.dp, vertical = 3.dp),
    ) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(CircleShape)
                .background(Color(0xFFFF3B30).copy(alpha = pulse)),
        )
        Text(
            text = "LIVE",
            style = MaterialTheme.typography.labelSmall.copy(
                color = Color.White,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
    }
}

@Composable
private fun TitleBlock(name: String) {
    Column {
        Text(
            text = name,
            style = MaterialTheme.typography.displaySmall.copy(
                color = Color.White,
                fontFamily = PixoraFonts.Fraunces,
                fontStyle = FontStyle.Italic,
                fontWeight = FontWeight.W400,
            ),
        )
        Text(
            text = "◆ 4K · LIVE WALLPAPER",
            style = MaterialTheme.typography.labelSmall.copy(
                color = Color.White.copy(alpha = 0.78f),
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W600,
            ),
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

@Composable
private fun StatsGlass(w: LiveWallpaper) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        StatChip(value = "${w.downloadCount ?: 0}", key = "DESCARGAS", modifier = Modifier.weight(1f))
        StatChip(value = "—", key = "LIKES", modifier = Modifier.weight(1f))
        StatChip(value = w.category.take(4).uppercase(), key = "CATEGORÍA", modifier = Modifier.weight(1f))
    }
}

@Composable
private fun StatChip(value: String, key: String, modifier: Modifier = Modifier) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Color(0x73141420))
            .border(
                width = 0.5.dp,
                color = PixoraColors.Gold.copy(alpha = 0.25f),
                shape = RoundedCornerShape(10.dp),
            )
            .padding(vertical = 8.dp, horizontal = 8.dp),
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleSmall.copy(
                color = Color.White,
                fontWeight = FontWeight.W800,
            ),
        )
        Text(
            text = key,
            style = MaterialTheme.typography.labelSmall.copy(
                color = Color.White.copy(alpha = 0.75f),
                fontFamily = PixoraFonts.JetBrainsMono,
            ),
            modifier = Modifier.padding(top = 2.dp),
        )
    }
}

@Composable
private fun ApplyGlass(onClick: () -> Unit) {
    val infinite = rememberInfiniteTransition(label = "cta")
    val breathe by infinite.animateFloat(
        initialValue = 0.85f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1500), RepeatMode.Reverse),
        label = "ctaBreathe",
    )
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(
                Brush.horizontalGradient(
                    listOf(
                        PixoraColors.Gold.copy(alpha = 0.42f * breathe),
                        PixoraColors.GoldBright.copy(alpha = 0.32f * breathe),
                    ),
                ),
            )
            .border(
                width = 1.dp,
                color = PixoraColors.GoldBright.copy(alpha = 0.6f),
                shape = RoundedCornerShape(16.dp),
            )
            .clickable { onClick() }
            .padding(vertical = 14.dp),
    ) {
        Text(
            text = "+ APLICAR LIVE WALLPAPER",
            style = MaterialTheme.typography.titleSmall.copy(
                color = Color.White,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W800,
            ),
        )
    }
}

@Composable
private fun ActionFloats(
    onDownload: () -> Unit,
    onFavorite: () -> Unit,
    onShare: () -> Unit,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        FloatButton(Icons.Outlined.FileDownload, onDownload, Modifier.weight(1f))
        FloatButton(Icons.Outlined.FavoriteBorder, onFavorite, Modifier.weight(1f))
        FloatButton(Icons.Outlined.Share, onShare, Modifier.weight(1f))
    }
}

@Composable
private fun FloatButton(
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(44.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0x6B141420))
            .border(
                width = 0.5.dp,
                color = PixoraColors.Gold.copy(alpha = 0.25f),
                shape = RoundedCornerShape(12.dp),
            )
            .clickable { onClick() },
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = PixoraColors.GoldBright,
            modifier = Modifier.size(20.dp),
        )
    }
}
