package com.orbix.pixora.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.orbix.pixora.ui.theme.PixoraColors

/**
 * Heart button — toggles favorite for any card. 30dp dark circle
 * with the appropriate icon; scales 1→1.15→1 on tap for tactile feel.
 *
 * Caller owns the state ([isFavorite]) and the toggle effect — this
 * just renders + emits a click.
 */
@Composable
fun HeartButton(
    isFavorite: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scale by animateFloatAsState(
        targetValue = if (isFavorite) 1.12f else 1f,
        animationSpec = tween(180),
        label = "heartScale",
    )
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(30.dp)
            .clip(CircleShape)
            .background(Color(0x99000000))
            .clickable { onToggle() }
            .scale(scale),
    ) {
        Icon(
            imageVector = if (isFavorite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
            contentDescription = if (isFavorite) "Quitar de favoritos" else "Agregar a favoritos",
            tint = if (isFavorite) PixoraColors.Ruby else PixoraColors.GoldBright,
            modifier = Modifier.size(18.dp),
        )
    }
}
