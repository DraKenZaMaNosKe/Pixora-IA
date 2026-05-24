package com.orbix.pixora.features.favorites

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts

/**
 * Favoritos — "Cabinet of Curiosities" (Wunderkammer) empty state.
 *
 * Aesthetic: museum cabinet ledger. Doc code top, Fraunces italic
 * counter "0 piezas catalogadas · MMXXVI", framed empty plate with
 * heart icon centered, instructions in Cormorant italic.
 *
 * When Room favorites land, the empty plate becomes a 2-col grid of
 * specimen cards (border + roman numeral N.º + tag chip + image).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen() {
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
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = 20.dp),
        ) {
            Spacer(Modifier.height(8.dp))
            CounterRow(count = 0)
            Spacer(Modifier.height(20.dp))
            EmptyPlate()
        }
    }
}

@Composable
private fun CounterRow(count: Int) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxWidth(),
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
        // Inner double-frame line
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
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(PixoraColors.GoldHaze)
                    .border(
                        width = 0.8.dp,
                        color = PixoraColors.GoldBright.copy(alpha = 0.6f),
                        shape = androidx.compose.foundation.shape.CircleShape,
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
                style = MaterialTheme.typography.bodySmall.copy(
                    color = PixoraColors.TextFaint,
                ),
                textAlign = TextAlign.Center,
            )
        }
    }
}
