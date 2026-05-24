package com.orbix.pixora.features.live

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
import androidx.compose.foundation.layout.size
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
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.theme.PixoraColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import com.orbix.pixora.ui.theme.PixoraFonts
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.orbix.pixora.data.models.LiveWallpaper
import com.orbix.pixora.ui.components.HeroCarousel
import com.orbix.pixora.ui.components.ShimmerImage
import androidx.compose.runtime.remember

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LiveScreen(
    onLiveClick: (String) -> Unit = {},
    viewModel: LiveViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    Scaffold(
        containerColor = PixoraColors.Ink,
        topBar = {
            PixoraAppBar(
                title = "Live Wallpapers",
                eyebrow = "// PIXORA · EN MOVIMIENTO",
                subtitle = if (state.items.isEmpty()) null
                    else "${state.items.size} videos · loop perfecto",
                accentColor = PixoraColors.AuroraMagenta,
            )
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                state.loading && state.items.isEmpty() -> CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.errorMsg != null && state.items.isEmpty() -> Text(
                    text = state.errorMsg!!,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> LiveGrid(state.items, onLiveClick)
            }
        }
    }
}

@Composable
private fun LiveGrid(items: List<LiveWallpaper>, onClick: (String) -> Unit) {
    val heroPool = remember(items) {
        // Prefer NEW badges, then top 5 by sortOrder; cap at 6.
        val news = items.filter { it.badge?.uppercase() == "NEW" }
        (if (news.size >= 3) news else items).take(6)
    }
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        if (heroPool.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                HeroCarousel(
                    items = heroPool,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 11f),
                ) { hero ->
                    LiveHeroCard(hero) { onClick(hero.id) }
                }
            }
        }
        items(items, key = { it.id }) { item -> LiveProCard(item) { onClick(item.id) } }
    }
}

/**
 * Hero-sized version of LiveProCard — wider aspect ratio (16:11) so the
 * pulsing LIVE badge + title + GET CTA breathe more. Reuses the same
 * visual language as the cards but oriented landscape.
 */
@Composable
private fun LiveHeroCard(item: LiveWallpaper, onClick: () -> Unit) {
    val glow = runCatching { Color(android.graphics.Color.parseColor(item.glowColor)) }
        .getOrDefault(PixoraColors.AuroraMagenta)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(16f / 11f)
            .clip(RoundedCornerShape(16.dp))
            .background(PixoraColors.Surface)
            .clickable { onClick() },
    ) {
        ShimmerImage(
            url = item.previewUrl,
            contentDescription = item.name,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(140.dp)
                .align(Alignment.BottomCenter)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color(0xEE000000)),
                    ),
                ),
        )
        // Bottom: title + category + GET CTA
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(16.dp),
        ) {
            Text(
                text = "// PIXORA · EN MOVIMIENTO",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = glow,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
            Text(
                text = item.name,
                style = MaterialTheme.typography.headlineSmall.copy(
                    color = Color.White,
                    fontWeight = FontWeight.W900,
                ),
                maxLines = 2,
            )
        }
        // LIVE pill top-left
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .padding(12.dp)
                .clip(RoundedCornerShape(50))
                .background(Color(0xCC000000))
                .padding(horizontal = 8.dp, vertical = 4.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(Color(0xFFE53935)),
            )
            Spacer(Modifier.size(6.dp))
            Text(
                text = "LIVE",
                style = MaterialTheme.typography.labelMedium.copy(
                    color = Color.White,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W800,
                ),
            )
        }
    }
}

/**
 * App Store Pro Window — Live wallpaper card with:
 *   - Outer glow border using item.glowColor
 *   - Pulsing LIVE indicator (red dot + LIVE label)
 *   - Bottom plate: title in Geist W700 + category in JetBrains Mono +
 *     "GET" CTA chip in gold
 */
@Composable
private fun LiveProCard(item: LiveWallpaper, onClick: () -> Unit) {
    val context = LocalContext.current
    val glow = runCatching { Color(android.graphics.Color.parseColor(item.glowColor)) }
        .getOrDefault(PixoraColors.AuroraMagenta)

    Box(
        modifier = Modifier
            .fillMaxSize()
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
            .clickable { onClick() },
    ) {
        ShimmerImage(
            url = item.previewUrl,
            contentDescription = item.name,
            modifier = Modifier.fillMaxSize(),
        )

        // Bottom scrim
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

        // Title + category + GET chip row
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(10.dp),
        ) {
            Text(
                text = item.name,
                style = MaterialTheme.typography.titleSmall.copy(
                    color = Color.White,
                    fontWeight = FontWeight.W700,
                ),
                maxLines = 2,
            )
            Spacer(Modifier.height(4.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = item.category.uppercase(),
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = glow.copy(alpha = 0.9f),
                        fontFamily = PixoraFonts.JetBrainsMono,
                    ),
                )
                GetChip()
            }
        }

        // LIVE badge top-left — red dot + label in pill
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .padding(6.dp)
                .clip(RoundedCornerShape(50))
                .background(Color(0xCC000000))
                .border(
                    width = 0.5.dp,
                    color = Color(0xFFE53935).copy(alpha = 0.6f),
                    shape = RoundedCornerShape(50),
                )
                .padding(horizontal = 6.dp, vertical = 3.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(Color(0xFFE53935)),
            )
            Spacer(Modifier.size(4.dp))
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
}

@Composable
private fun GetChip() {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(PixoraColors.GoldBright)
            .padding(horizontal = 10.dp, vertical = 3.dp),
    ) {
        Text(
            text = "GET",
            style = MaterialTheme.typography.labelSmall.copy(
                color = PixoraColors.Ink,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W800,
            ),
        )
    }
}
