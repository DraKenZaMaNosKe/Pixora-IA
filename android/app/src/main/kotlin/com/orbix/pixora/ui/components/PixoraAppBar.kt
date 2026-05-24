package com.orbix.pixora.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.orbix.pixora.data.credits.CreditService
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

/**
 * Pixora signature app bar — replaces every TopAppBar in the app.
 *
 * Anatomy (top to bottom):
 *   1. Thin iridescent ribbon (1px, gradient gold → aurora cyan → gold).
 *      Subtle but unmistakable Pixora brand mark on every screen.
 *   2. Eyebrow row: doc-code label (JetBrains Mono uppercase) + diamond
 *      pill showing CreditService.balance (always-visible 💎 N).
 *   3. Title row: Fraunces italic display with optional gold-gradient
 *      tint. Subtitle in Geist below if provided.
 *
 * Designed so EVERY section feels editorial + premium without each tab
 * having to reinvent its header. Per-section accent comes from the
 * `accentColor` parameter (drives the ribbon's middle stop).
 */
@Composable
fun PixoraAppBar(
    title: String,
    modifier: Modifier = Modifier,
    eyebrow: String? = null,
    subtitle: String? = null,
    accentColor: Color = PixoraColors.AuroraCyan,
    showCreditsPill: Boolean = true,
    creditsViewModel: PixoraAppBarCreditsViewModel = hiltViewModel(),
) {
    val balance by creditsViewModel.balance.collectAsStateWithLifecycle(initialValue = 0L)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(PixoraColors.Ink)
            .padding(top = 0.dp)
    ) {
        IridescentRibbon(accentColor)

        // Eyebrow row + credits pill
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text(
                text = eyebrow ?: "// PIXORA",
                style = MaterialTheme.typography.labelSmall.copy(color = PixoraColors.GoldDeep),
                maxLines = 1,
            )
            if (showCreditsPill) DiamondPill(balance = balance)
        }

        // Title row
        Text(
            text = buildAnnotatedString {
                // Fraunces italic display with subtle gold tint on first word
                val firstSpace = title.indexOf(' ')
                if (firstSpace > 0) {
                    withStyle(SpanStyle(color = PixoraColors.GoldBright)) {
                        append(title.substring(0, firstSpace))
                    }
                    withStyle(SpanStyle(color = PixoraColors.TextPrimary)) {
                        append(title.substring(firstSpace))
                    }
                } else {
                    withStyle(SpanStyle(color = PixoraColors.TextPrimary)) {
                        append(title)
                    }
                }
            },
            style = MaterialTheme.typography.displayMedium.copy(fontStyle = FontStyle.Italic),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, bottom = if (subtitle == null) 12.dp else 4.dp),
        )

        if (subtitle != null) {
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodyMedium.copy(color = PixoraColors.TextSecondary),
                maxLines = 2,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
            )
        }
    }
}

@Composable
private fun IridescentRibbon(accent: Color) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(2.dp)
            .background(
                Brush.horizontalGradient(
                    colors = listOf(
                        PixoraColors.GoldDeep,
                        PixoraColors.Gold,
                        PixoraColors.GoldBright,
                        accent,
                        PixoraColors.GoldBright,
                        PixoraColors.Gold,
                        PixoraColors.GoldDeep,
                    ),
                ),
            ),
    )
}

@Composable
private fun DiamondPill(balance: Long) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(
                Brush.horizontalGradient(
                    colors = listOf(
                        PixoraColors.GoldHaze,
                        PixoraColors.GoldDeep.copy(alpha = 0.3f),
                    ),
                ),
            )
            .padding(horizontal = 10.dp, vertical = 4.dp),
    ) {
        Text(
            text = "◆",
            color = PixoraColors.GoldBright,
            fontWeight = FontWeight.Bold,
            fontSize = MaterialTheme.typography.labelMedium.fontSize,
        )
        Text(
            text = " $balance",
            style = MaterialTheme.typography.labelMedium.copy(
                color = PixoraColors.GoldBright,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W600,
            ),
        )
    }
}

@HiltViewModel
class PixoraAppBarCreditsViewModel @Inject constructor(
    creditService: CreditService,
) : ViewModel() {
    val balance: Flow<Long> = creditService.balance
}
