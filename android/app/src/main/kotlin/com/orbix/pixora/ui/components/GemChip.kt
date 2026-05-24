package com.orbix.pixora.ui.components

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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts

/**
 * Gem palette — Pixora's category-chip identity. Each chip is a "gem"
 * with a 4-stop ramp (base / deep / bright / pale). Matches v1's
 * "Multi-Gem Collection" design (Trending=Topaz, New=Sapphire,
 * Arte=Ruby, Mito=Emerald, etc.).
 */
enum class Gem(val base: Color, val deep: Color, val bright: Color, val pale: Color) {
    Topaz(PixoraColors.Topaz, PixoraColors.TopazDeep, PixoraColors.TopazBright, PixoraColors.TopazPale),
    Sapphire(PixoraColors.Sapphire, PixoraColors.SapphireDeep, PixoraColors.SapphireBright, PixoraColors.SapphirePale),
    Ruby(PixoraColors.Ruby, PixoraColors.RubyDeep, PixoraColors.RubyBright, PixoraColors.RubyPale),
    Emerald(PixoraColors.Emerald, PixoraColors.EmeraldDeep, PixoraColors.EmeraldBright, PixoraColors.EmeraldPale),
    Amethyst(PixoraColors.AuroraViolet, Color(0xFF4A3580), PixoraColors.AuroraLavender, Color(0xFFE6DEF7)),
    Onyx(PixoraColors.TextSecondary, PixoraColors.TextFaint, PixoraColors.TextPrimary, PixoraColors.TextPrimary),
}

/**
 * Single gem chip — pill with dot + label + optional count badge.
 *
 * Selected state: filled with deep tint, border bright, label bright,
 * dot glows in brand color. Unselected: ink background, deep border,
 * pale text. Stagger your row's chips with [delayMs] so the glow
 * pulses out of phase (Zelda chest-of-gems vibe).
 */
@Composable
fun GemChip(
    label: String,
    gem: Gem,
    selected: Boolean,
    count: Int? = null,
    delayMs: Int = 0,
    onClick: () -> Unit,
) {
    val infinite = rememberInfiniteTransition(label = "gemPulse_$label")
    val pulse by infinite.animateFloat(
        initialValue = 0.55f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1600, delayMillis = delayMs),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulse",
    )

    val borderColor = if (selected) gem.bright else gem.deep.copy(alpha = 0.55f)
    val textColor = if (selected) gem.bright else gem.deep.copy(alpha = 0.85f)
    val bgBrush = remember(selected) {
        if (selected) Brush.verticalGradient(
            listOf(
                gem.deep.copy(alpha = 0.25f),
                Color.Transparent,
            )
        ) else Brush.verticalGradient(listOf(Color.Transparent, Color.Transparent))
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(bgBrush)
            .border(
                width = if (selected) 1.2.dp else 0.7.dp,
                color = borderColor,
                shape = RoundedCornerShape(50),
            )
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        // Glowing dot
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(gem.base.copy(alpha = pulse)),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(
                color = textColor,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
        if (count != null) {
            Text(
                text = "$count",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = textColor.copy(alpha = 0.7f),
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
            )
        }
    }
}

