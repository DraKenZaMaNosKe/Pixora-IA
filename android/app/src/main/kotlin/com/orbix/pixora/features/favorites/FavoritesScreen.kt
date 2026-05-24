package com.orbix.pixora.features.favorites

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.orbix.pixora.data.db.FavoriteEntity
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.components.ShimmerImage
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen(viewModel: FavoritesViewModel = hiltViewModel()) {
    val items by viewModel.items.collectAsStateWithLifecycle(initialValue = emptyList())

    Scaffold(
        containerColor = PixoraColors.Ink,
        topBar = {
            PixoraAppBar(
                title = "Wunderkammer",
                eyebrow = "// CABINET · WUNDERKAMMER",
                subtitle = "Tu colección personal de piezas que te enamoraron",
                accentColor = PixoraColors.AuroraRose,
            )
        },
    ) { inner ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner),
        ) {
            if (items.isEmpty()) {
                EmptyState()
            } else {
                FavoritesGrid(
                    items = items,
                    onRemove = viewModel::remove,
                )
            }
        }
    }
}

@Composable
private fun EmptyState() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(8.dp))
        CounterRow(count = 0)
        Spacer(Modifier.height(20.dp))
        EmptyPlate()
    }
}

@Composable
private fun FavoritesGrid(
    items: List<FavoriteEntity>,
    onRemove: (String) -> Unit,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            CounterRow(count = items.size)
        }
        items(items, key = { it.id }) { fav ->
            SpecimenCard(fav, onRemove)
        }
    }
}

@Composable
private fun CounterRow(count: Int) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
    ) {
        Text(
            text = "ENTRADAS",
            style = MaterialTheme.typography.labelSmall.copy(
                color = PixoraColors.GoldBright,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
        Box(
            modifier = Modifier
                .height(1.dp)
                .weight(1f)
                .background(
                    Brush.horizontalGradient(
                        listOf(PixoraColors.GoldBright.copy(alpha = 0.5f), Color.Transparent),
                    ),
                ),
        )
        Text(
            text = "$count · MMXXVI",
            style = MaterialTheme.typography.labelSmall.copy(
                color = PixoraColors.TextSecondary,
                fontFamily = PixoraFonts.JetBrainsMono,
            ),
        )
    }
}

@Composable
private fun EmptyPlate() {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .height(420.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(PixoraColors.Surface)
            .border(
                width = 0.7.dp,
                color = PixoraColors.GoldBright.copy(alpha = 0.5f),
                shape = RoundedCornerShape(14.dp),
            ),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(12.dp)
                .border(
                    width = 0.5.dp,
                    color = PixoraColors.GoldDeep.copy(alpha = 0.6f),
                    shape = RoundedCornerShape(10.dp),
                ),
        )
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = Modifier.padding(32.dp),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape)
                    .background(PixoraColors.GoldHaze)
                    .border(
                        width = 0.8.dp,
                        color = PixoraColors.GoldBright.copy(alpha = 0.6f),
                        shape = CircleShape,
                    ),
            ) {
                Icon(
                    imageVector = Icons.Outlined.FavoriteBorder,
                    contentDescription = null,
                    tint = PixoraColors.GoldBright,
                    modifier = Modifier.size(40.dp),
                )
            }
            Text(
                text = "GABINETE VACÍO",
                style = MaterialTheme.typography.titleMedium.copy(
                    color = PixoraColors.TextPrimary,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W800,
                ),
            )
            Text(
                text = "Aquí guardamos tus piezas favoritas",
                style = MaterialTheme.typography.bodyMedium.copy(
                    color = PixoraColors.TextSecondary,
                    fontFamily = PixoraFonts.CormorantItalic,
                    fontStyle = FontStyle.Italic,
                ),
                textAlign = TextAlign.Center,
            )
            Text(
                text = "Toca el corazón en cualquier wallpaper, live, tono o frecuencia AURA y empieza tu colección.",
                style = MaterialTheme.typography.bodySmall.copy(color = PixoraColors.TextFaint),
                textAlign = TextAlign.Center,
            )
        }
    }
}

private val romanDigits = listOf(
    1000 to "M", 900 to "CM", 500 to "D", 400 to "CD",
    100 to "C", 90 to "XC", 50 to "L", 40 to "XL",
    10 to "X", 9 to "IX", 5 to "V", 4 to "IV", 1 to "I",
)
private fun Int.toRoman(): String {
    var n = this
    val sb = StringBuilder()
    for ((v, sym) in romanDigits) {
        while (n >= v) { sb.append(sym); n -= v }
    }
    return sb.toString()
}

@Composable
private fun SpecimenCard(fav: FavoriteEntity, onRemove: (String) -> Unit) {
    val accent = runCatching { Color(android.graphics.Color.parseColor(fav.accentHex)) }
        .getOrDefault(PixoraColors.GoldBright)
    val romanIdx = (fav.addedAt % 999).toInt().coerceAtLeast(1).toRoman()
    val tag = when (fav.kind) {
        FavoriteEntity.KIND_WALLPAPER -> "WALLPAPER"
        FavoriteEntity.KIND_LIVE -> "LIVE"
        FavoriteEntity.KIND_AURA -> "AURA"
        FavoriteEntity.KIND_TONE -> "TONO"
        FavoriteEntity.KIND_STORY -> "HISTORIA"
        FavoriteEntity.KIND_DAYCYCLE -> "CICLO"
        else -> "PIEZA"
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(PixoraColors.Surface)
            .border(
                width = 0.6.dp,
                color = accent.copy(alpha = 0.5f),
                shape = RoundedCornerShape(12.dp),
            )
            .clickable { /* TODO open detail by kind */ },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(9f / 16f),
        ) {
            ShimmerImage(
                url = fav.previewUrl,
                contentDescription = fav.name,
                modifier = Modifier.fillMaxSize(),
            )
            // Top-right tag pill
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Color(0xCC000000))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            ) {
                Text(
                    text = tag,
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = accent,
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W700,
                    ),
                )
            }
            // Top-left roman numeral (specimen number)
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(6.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Color(0xCC000000))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            ) {
                Text(
                    text = "N.º $romanIdx",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = PixoraColors.GoldBright,
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W700,
                    ),
                )
            }
            // Bottom-right remove (delete) chip
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(6.dp)
                    .clip(CircleShape)
                    .background(Color(0xCC000000))
                    .clickable { onRemove(fav.id) }
                    .padding(6.dp),
            ) {
                Icon(
                    imageVector = Icons.Outlined.FavoriteBorder,
                    contentDescription = "Quitar",
                    tint = PixoraColors.Ruby,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
        Column(Modifier.padding(8.dp)) {
            Text(
                text = fav.name,
                style = MaterialTheme.typography.titleSmall.copy(
                    color = PixoraColors.TextPrimary,
                    fontFamily = PixoraFonts.Fraunces,
                    fontStyle = FontStyle.Italic,
                ),
                maxLines = 1,
            )
            Text(
                text = "// $tag",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = accent,
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}
