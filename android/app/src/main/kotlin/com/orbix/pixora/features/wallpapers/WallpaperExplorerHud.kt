package com.orbix.pixora.features.wallpapers

import android.app.Activity
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
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.orbix.pixora.data.models.Wallpaper
import com.orbix.pixora.ui.components.DownloadManagerOverlay
import com.orbix.pixora.ui.theme.PixoraFonts

/**
 * Wallpaper Explorer HUD — Neon HUD Professional concept #5.
 *
 * Full-screen, swipeable browser triggered by tapping a CHIP in a section
 * (per doc §12.29). NOT triggered by individual card taps — those keep
 * the Trading Card detail.
 *
 * Architecture:
 *   - HorizontalPager swipes through the wallpapers in the active category
 *   - Each page = HUD frame + target image + author + stats + ACQUIRE
 *   - Apply flow preserved (AdMob gated → CreditService.earnFromAd)
 *   - ESC closes the modal (popBackStack)
 *
 * Visual: cyber-tactical, cyan + amber, JetBrains Mono everywhere. The
 * pager itself is invisible — what the user feels is "swiping through
 * the gallery", not navigating between detail pages.
 */
private val HudInk = Color(0xFF02050A)
private val HudCyan = Color(0xFF00E5FF)
private val HudAmber = Color(0xFFFFB400)
private val HudCyanFaint = Color(0x3300E5FF)

@Composable
fun WallpaperExplorerHud(
    categoryFilter: String?,
    initialId: String?,
    onClose: () -> Unit,
    viewModel: WallpapersViewModel = hiltViewModel(),
    detailViewModel: WallpaperDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val detailState by detailViewModel.state.collectAsStateWithLifecycle()
    val snackHost = remember { SnackbarHostState() }
    val activity = LocalContext.current as? Activity

    val items = remember(state.wallpapers, categoryFilter) {
        if (categoryFilter == null) state.wallpapers
        else state.wallpapers.filter {
            it.category.equals(categoryFilter, ignoreCase = true) ||
            it.tags.any { tag -> tag.equals(categoryFilter, ignoreCase = true) }
        }
    }

    val initialPage = remember(items, initialId) {
        items.indexOfFirst { it.id == initialId }.coerceAtLeast(0)
    }

    val pagerState = rememberPagerState(initialPage = initialPage) { items.size }

    LaunchedEffect(detailState.event) {
        when (val e = detailState.event) {
            is DetailEvent.Toast -> {
                snackHost.showSnackbar(e.message)
                detailViewModel.consumeEvent()
            }
            null -> Unit
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(HudInk),
    ) {
        if (items.isEmpty()) {
            Text(
                text = "// NO_TARGETS_IN_CATEGORY",
                color = HudAmber,
                style = MaterialTheme.typography.labelMedium.copy(
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
                modifier = Modifier.align(Alignment.Center),
            )
            return@Box
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.statusBars),
        ) {
            HudTopBar(
                onBack = onClose,
                categoryLabel = (categoryFilter ?: "ALL").uppercase(),
                currentIndex = pagerState.currentPage + 1,
                total = items.size,
            )
            HudChipsRowStatic(active = categoryFilter)
            HorizontalPager(
                state = pagerState,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            ) { page ->
                val w = items[page]
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                    ) {
                        TargetFrame(w)
                    }
                    Spacer(Modifier.height(8.dp))
                    HudStats(w)
                }
            }
            HudActionRow(
                state = detailState,
                onApply = { activity?.let { detailViewModel.apply(it) } },
            )
            HudSponsorStrip()
            Spacer(
                Modifier
                    .fillMaxWidth()
                    .windowInsetsPadding(WindowInsets.navigationBars)
                    .height(0.dp),
            )
        }

        SnackbarHost(
            hostState = snackHost,
            modifier = Modifier.align(Alignment.BottomCenter),
        )

        // Download manager overlay on top
        DownloadManagerOverlay(
            stage = detailState.downloadStage,
            errorMessage = detailState.downloadError,
        )
    }
}

@Composable
private fun HudTopBar(onBack: () -> Unit, categoryLabel: String, currentIndex: Int, total: Int) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0x0500E5FF))
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Text(
            text = "‹ ESC",
            style = MaterialTheme.typography.labelMedium.copy(
                color = HudCyan,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
            modifier = Modifier.clickable { onBack() },
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FlickerDot()
            Text(
                text = "TARGET $currentIndex / $total · $categoryLabel",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = HudCyan,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
        }
        Text(
            text = "⇆ SWIPE",
            style = MaterialTheme.typography.labelSmall.copy(
                color = HudAmber,
                fontFamily = PixoraFonts.JetBrainsMono,
            ),
        )
    }
    HudHairline()
}

@Composable
private fun FlickerDot() {
    val infinite = rememberInfiniteTransition(label = "flicker")
    val alpha by infinite.animateFloat(
        initialValue = 0.4f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(800), RepeatMode.Reverse),
        label = "flickerA",
    )
    Box(
        modifier = Modifier
            .size(6.dp)
            .background(HudCyan.copy(alpha = alpha)),
    )
}

@Composable
private fun HudChipsRowStatic(active: String?) {
    val labels = listOf("TRENDING", "NEW", "ARTE", "MITO", "ANIME", "GAMING", "PANO", "DARK")
    LazyRow(
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(0.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        items(labels) { lbl ->
            val on = lbl.equals(active, ignoreCase = true)
            Box(
                modifier = Modifier
                    .background(if (on) HudCyan else Color.Transparent)
                    .border(0.8.dp, if (on) HudCyan else HudCyanFaint)
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            ) {
                Text(
                    text = lbl,
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = if (on) HudInk else HudCyan.copy(alpha = 0.55f),
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W700,
                    ),
                )
            }
        }
    }
    HudHairline()
}

private fun androidx.compose.foundation.lazy.LazyListScope.items(
    items: List<String>,
    itemContent: @Composable (String) -> Unit,
) {
    items(count = items.size) { i -> itemContent(items[i]) }
}

@Composable
private fun TargetFrame(w: Wallpaper) {
    val context = LocalContext.current
    Box(
        modifier = Modifier
            .fillMaxSize()
            .border(1.dp, HudCyan)
            .padding(6.dp),
    ) {
        AsyncImage(
            model = ImageRequest.Builder(context).data(w.imageUrl).crossfade(true).build(),
            contentDescription = w.name,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        CornerBracket(Alignment.TopStart)
        CornerBracket(Alignment.TopEnd)
        CornerBracket(Alignment.BottomStart)
        CornerBracket(Alignment.BottomEnd)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomStart)
                .background(Color(0xCC000000))
                .padding(horizontal = 8.dp, vertical = 6.dp),
        ) {
            Text(
                text = "ID: ${w.id.uppercase().take(12)}",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = HudCyan,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
            Text(
                text = "AUTHOR ${w.authorName.uppercase().take(16)}",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = HudAmber,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.BoxScope.CornerBracket(alignment: Alignment) {
    val isLeft = alignment == Alignment.TopStart || alignment == Alignment.BottomStart
    val isTop = alignment == Alignment.TopStart || alignment == Alignment.TopEnd
    Box(
        modifier = Modifier
            .size(16.dp)
            .align(alignment)
            .drawWithContent {
                val s = 2.dp.toPx()
                val w = size.width
                val h = size.height
                if (isTop) drawRect(HudAmber, topLeft = Offset(0f, 0f), size = Size(w, s))
                else drawRect(HudAmber, topLeft = Offset(0f, h - s), size = Size(w, s))
                if (isLeft) drawRect(HudAmber, topLeft = Offset(0f, 0f), size = Size(s, h))
                else drawRect(HudAmber, topLeft = Offset(w - s, 0f), size = Size(s, h))
            },
    )
}

@Composable
private fun HudStats(w: Wallpaper) {
    Row(
        horizontalArrangement = Arrangement.SpaceBetween,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp),
    ) {
        StatItem("RATING", "4.8★")
        StatItem("DL", "${w.installCount ?: w.viewCount ?: 0}")
        StatItem("RARITY", if (w.featured) "EPIC" else if (w.isPanoramic) "LEGENDARY" else "RARE")
    }
}

@Composable
private fun StatItem(label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(
                color = HudCyan.copy(alpha = 0.7f),
                fontFamily = PixoraFonts.JetBrainsMono,
            ),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.labelSmall.copy(
                color = HudAmber,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
    }
}

@Composable
private fun HudActionRow(state: WallpaperDetailUiState, onApply: () -> Unit) {
    HudHairline()
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        ActionSquare("↗")
        ActionSquare("♡")
        AcquireButton(state = state, onClick = onApply, modifier = Modifier.weight(1f))
        ActionSquare("⋯")
    }
}

@Composable
private fun ActionSquare(symbol: String) {
    Box(
        modifier = Modifier
            .size(38.dp)
            .border(1.dp, HudCyan)
            .background(Color(0x0A00E5FF)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = symbol,
            style = MaterialTheme.typography.titleMedium.copy(
                color = HudCyan,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
    }
}

@Composable
private fun AcquireButton(state: WallpaperDetailUiState, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val (bg, fg, label) = when {
        state.applying -> Triple(HudAmber.copy(alpha = 0.5f), HudInk, "▶ APPLYING…")
        state.justApplied -> Triple(Color(0xFF10B981), HudInk, "✓ ACQUIRED")
        else -> Triple(HudAmber, HudInk, "▶ ACQUIRE")
    }
    val infinite = rememberInfiniteTransition(label = "acquire")
    val pulse by infinite.animateFloat(
        initialValue = 0.85f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1400), RepeatMode.Reverse),
        label = "acquirePulse",
    )
    Box(
        modifier = modifier
            .height(38.dp)
            .background(bg)
            .border(1.dp, HudAmber.copy(alpha = pulse))
            .clickable(enabled = !state.applying && !state.justApplied) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium.copy(
                color = fg,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W800,
            ),
        )
    }
}

@Composable
private fun HudSponsorStrip() {
    HudHairline()
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(
                modifier = Modifier
                    .border(0.8.dp, HudAmber)
                    .padding(horizontal = 5.dp, vertical = 2.dp),
            ) {
                Text(
                    text = "SPONSOR",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = HudAmber,
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W700,
                    ),
                )
            }
            Text(
                text = "Pixora · Premium colección",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = HudCyan.copy(alpha = 0.7f),
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
            )
        }
        Text(
            text = "VIEW →",
            style = MaterialTheme.typography.labelSmall.copy(
                color = HudAmber,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
    }
}

@Composable
private fun HudHairline() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(HudCyanFaint),
    )
}

