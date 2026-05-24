package com.orbix.pixora.features.wallpapers

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import com.orbix.pixora.data.models.Wallpaper
import com.orbix.pixora.ui.components.EditorialHeroBanner
import com.orbix.pixora.ui.components.Gem
import com.orbix.pixora.ui.components.GemChip
import com.orbix.pixora.ui.components.HeartButton
import com.orbix.pixora.ui.components.HeroCarousel
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.components.ShimmerImage
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts

/**
 * Wallpapers grid + category-chip filter row.
 *
 * Card design follows v1's "Trading Card Holo" — every card is a
 * collectible specimen with a serial number, badges, glow accent
 * sourced from `wallpaper.glowColor`, and an "ADMIT · ONE" ticket
 * sub-label. The aesthetic frames each wallpaper as a curated piece.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WallpapersScreen(
    onWallpaperClick: (String) -> Unit = {},
    onChipExplore: (category: String?, firstId: String?) -> Unit = { _, _ -> },
    viewModel: WallpapersViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val favoriteIds by viewModel.favoriteIds.collectAsStateWithLifecycle()
    var selectedCategory by remember { mutableStateOf<String?>(null) }
    val filtered = remember(state.wallpapers, selectedCategory) {
        if (selectedCategory == null) state.wallpapers
        else state.wallpapers.filter {
            it.category.equals(selectedCategory, ignoreCase = true) ||
            it.tags.any { tag -> tag.equals(selectedCategory, ignoreCase = true) }
        }
    }

    Scaffold(
        containerColor = PixoraColors.Ink,
        topBar = {
            PixoraAppBar(
                title = "Pixora Wallpapers",
                eyebrow = "// PIXORA · GALERÍA",
                subtitle = if (state.wallpapers.isEmpty()) null
                    else "Cientos de fondos para tu pantalla",
                accentColor = PixoraColors.GoldBright,
            )
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                state.loading && state.wallpapers.isEmpty() -> LoadingState()
                state.errorMsg != null && state.wallpapers.isEmpty() -> ErrorState(state.errorMsg!!)
                else -> {
                    // Hero pool — featured wallpapers (fallback to full set
                    // when fewer than 3 featured exist). HeroCarousel handles
                    // auto-advance + manual swipe internally.
                    val heroPool = remember(state.wallpapers) {
                        val featured = state.wallpapers.filter { it.featured }
                        val pool = if (featured.size >= 3) featured else state.wallpapers
                        pool.take(8)  // cap so we don't render 280 dots
                    }

                    WallpapersGridWithHero(
                        items = filtered,
                        heroPool = heroPool,
                        selectedCategory = selectedCategory,
                        favoriteIds = favoriteIds,
                        onSelectCategory = { cat ->
                            val firstInCat = state.wallpapers.firstOrNull {
                                cat == null ||
                                it.category.equals(cat, ignoreCase = true) ||
                                it.tags.any { tag -> tag.equals(cat, ignoreCase = true) }
                            }
                            onChipExplore(cat, firstInCat?.id)
                        },
                        onWallpaperClick = onWallpaperClick,
                        onExploreAll = { onChipExplore(null, heroPool.firstOrNull()?.id) },
                        onToggleFavorite = viewModel::toggleFavorite,
                    )
                    if (filtered.isEmpty()) {
                        Text(
                            text = "Sin piezas en esta categoría",
                            style = MaterialTheme.typography.bodyMedium.copy(color = PixoraColors.TextSecondary),
                            modifier = Modifier.align(Alignment.Center),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadingState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(color = PixoraColors.GoldBright)
    }
}

@Composable
private fun ErrorState(msg: String) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = msg,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.error,
        )
    }
}

private data class CatChip(val label: String, val value: String?, val gem: Gem)

// Multi-Gem Collection (concept #5 from category_chips_gems.html). Each
// chip carries a distinct gem identity so the user can identify the
// category at a glance. Pulsing dots stagger by chip index.
private val WallpaperChips = listOf(
    CatChip("TODOS", null, Gem.Onyx),
    CatChip("TRENDING", "trending", Gem.Topaz),
    CatChip("NEW", "new", Gem.Sapphire),
    CatChip("PANORÁMICO", "PANORAMIC", Gem.Amethyst),
    CatChip("ANIME", "ANIME", Gem.Ruby),
    CatChip("GAMING", "GAMING", Gem.Emerald),
    CatChip("ARTE", "arte", Gem.Ruby),
    CatChip("MITOLOGÍA", "mitologia", Gem.Emerald),
    CatChip("CALENDAR", "CALENDAR", Gem.Sapphire),
    CatChip("NATURE", "NATURE", Gem.Emerald),
)

@Composable
private fun CategoryChipsRow(selected: String?, onSelect: (String?) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(WallpaperChips.size) { idx ->
            val chip = WallpaperChips[idx]
            GemChip(
                label = chip.label,
                gem = chip.gem,
                selected = chip.value == selected,
                // Stagger the pulse across chips for a "chest of gems" feel
                delayMs = idx * 200,
                onClick = { onSelect(chip.value) },
            )
        }
    }
}

@Composable
private fun WallpapersGridWithHero(
    items: List<Wallpaper>,
    heroPool: List<Wallpaper>,
    selectedCategory: String?,
    favoriteIds: Set<String>,
    onSelectCategory: (String?) -> Unit,
    onWallpaperClick: (String) -> Unit,
    onExploreAll: () -> Unit,
    onToggleFavorite: (Wallpaper) -> Unit,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        // Hero carousel — full-width row at top. User can swipe manually
        // or let auto-advance every 8s show the next cover.
        if (heroPool.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                HeroCarousel(
                    items = heroPool,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(4f / 5f),
                ) { cover ->
                    val (word1, word2) = splitTitle(cover.name)
                    EditorialHeroBanner(
                        imageUrl = cover.imageUrl,
                        titleWord1 = word1,
                        titleWord2 = word2,
                        volumeLabel = "VOL XII · ${"%03d".format(items.size)}",
                        blurbText = "Lo mejor de la colección, escogido por nosotros",
                        onCardTap = { onWallpaperClick(cover.id) },
                        onExploreTap = onExploreAll,
                    )
                }
            }
        }

        // Big "EXPLORADOR" entry below the hero
        item(span = { GridItemSpan(maxLineSpan) }) {
            ExplorerEntryButton(onClick = onExploreAll)
        }

        // Category chips row
        item(span = { GridItemSpan(maxLineSpan) }) {
            CategoryChipsRow(
                selected = selectedCategory,
                onSelect = onSelectCategory,
            )
        }

        // Grid of trading cards
        itemsIndexed(
            items = items,
            key = { _, w -> w.id },
        ) { index, wallpaper ->
            TradingCardHolo(
                wallpaper = wallpaper,
                serial = index + 1,
                isFavorite = wallpaper.id in favoriteIds,
                onToggleFavorite = { onToggleFavorite(wallpaper) },
                onClick = { onWallpaperClick(wallpaper.id) },
            )
        }
    }
}

/** Split "Aquarium Paradise" → ("Aquarium", "Paradise"). 1-word fallback. */
private fun splitTitle(title: String): Pair<String, String> {
    val space = title.indexOf(' ')
    return if (space > 0) title.substring(0, space) to title.substring(space + 1)
    else title to ""
}

@Composable
private fun ExplorerEntryButton(onClick: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(PixoraColors.GoldBright)
            .clickable { onClick() }
            .padding(horizontal = 16.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = "▶",
                style = MaterialTheme.typography.titleMedium.copy(
                    color = PixoraColors.Ink,
                    fontWeight = FontWeight.W900,
                ),
            )
            Text(
                text = "EXPLORADOR HUD",
                style = MaterialTheme.typography.labelLarge.copy(
                    color = PixoraColors.Ink,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W900,
                ),
            )
            Text(
                text = "·",
                style = MaterialTheme.typography.labelLarge.copy(color = PixoraColors.Ink),
            )
            Text(
                text = "todas las categorías",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = PixoraColors.Ink.copy(alpha = 0.7f),
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
            )
        }
    }
}

/**
 * Trading Card Holo — collectible card-style wallpaper preview.
 *
 * Anatomy:
 *   - Outer holo glow border using wallpaper.glowColor.
 *   - Image bleeds full-bleed inside the card.
 *   - Top-left badge stack: NEW or PANO or category-specific.
 *   - Top-right: serial number ("N° 042") in JetBrains Mono on a
 *     gold-haze pill.
 *   - Bottom strip: black gradient, then title in Fraunces italic +
 *     "ADMIT · ONE · ORBIX MMXXVI" doc-code in JetBrains Mono.
 */
@Composable
private fun TradingCardHolo(
    wallpaper: Wallpaper,
    serial: Int,
    isFavorite: Boolean,
    onToggleFavorite: () -> Unit,
    onClick: () -> Unit,
) {
    val context = LocalContext.current
    val glow = runCatching { Color(android.graphics.Color.parseColor(wallpaper.glowColor)) }
        .getOrDefault(PixoraColors.GoldBright)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(9f / 16f)
            .clip(RoundedCornerShape(14.dp))
            // Outer holo glow border — sits on top of the surface fill.
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
            url = wallpaper.previewUrl,
            contentDescription = wallpaper.name,
            modifier = Modifier.fillMaxSize(),
        )

        // Bottom scrim — taller (110dp) so we have room for title +
        // ADMIT line without the image getting obscured too high up.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(110.dp)
                .align(Alignment.BottomCenter)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color(0xEE000000)),
                    ),
                ),
        )

        // Bottom text block
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(10.dp),
        ) {
            Text(
                text = wallpaper.name,
                style = MaterialTheme.typography.titleSmall.copy(
                    fontFamily = PixoraFonts.Fraunces,
                    fontStyle = FontStyle.Italic,
                    color = Color.White,
                    fontWeight = FontWeight.W500,
                ),
                maxLines = 2,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                text = "ADMIT · ONE · ${wallpaper.authorName.uppercase()}",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = glow.copy(alpha = 0.9f),
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
                maxLines = 1,
            )
        }

        // Top-left badge stack
        Column(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(6.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (wallpaper.badge?.uppercase() == "NEW") {
                CornerBadge("NEW", PixoraColors.AuroraMagenta, Color.White)
            }
            if (wallpaper.isPanoramic) {
                CornerBadge("PANO", PixoraColors.GoldBright, PixoraColors.Ink)
            }
            if (wallpaper.featured) {
                CornerBadge("FEATURED", PixoraColors.AuroraCyan, PixoraColors.Ink)
            }
        }

        // Top-right column: heart (toggle) + serial pill below
        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(6.dp),
        ) {
            HeartButton(isFavorite = isFavorite, onToggle = onToggleFavorite)
            SerialPill(serial = serial, accent = glow)
        }
    }
}

@Composable
private fun CornerBadge(label: String, bg: Color, fg: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(bg)
            .padding(horizontal = 6.dp, vertical = 2.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(
                color = fg,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
    }
}

@Composable
private fun SerialPill(serial: Int, accent: Color, modifier: Modifier = Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(PixoraColors.Ink.copy(alpha = 0.7f))
            .border(
                width = 0.5.dp,
                color = accent.copy(alpha = 0.5f),
                shape = RoundedCornerShape(50),
            )
            .padding(horizontal = 8.dp, vertical = 3.dp),
    ) {
        Text(
            text = "N°",
            style = MaterialTheme.typography.labelSmall.copy(
                color = accent.copy(alpha = 0.7f),
                fontFamily = PixoraFonts.JetBrainsMono,
            ),
        )
        Spacer(Modifier.width(3.dp))
        Text(
            text = "%03d".format(serial),
            style = MaterialTheme.typography.labelSmall.copy(
                color = accent,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
    }
}
