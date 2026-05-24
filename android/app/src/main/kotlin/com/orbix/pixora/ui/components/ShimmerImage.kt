package com.orbix.pixora.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import coil3.compose.SubcomposeAsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.orbix.pixora.ui.theme.PixoraColors

/**
 * AsyncImage wrapper with a gold-haze shimmer placeholder while loading.
 *
 * Coil 3's SubcomposeAsyncImage exposes loading / success / error slots
 * we can fill with our own composables. While loading, paint a diagonal
 * gold-haze sweep that animates left→right (3-color gradient at offsets
 * driven by a 1.2s loop). On success, switch to the bitmap. On error,
 * paint the surface with a small dim icon.
 *
 * Use [ShimmerImage] in every grid card so the wait feels intentional
 * instead of a blank dark box.
 */
@Composable
fun ShimmerImage(
    url: String,
    contentDescription: String,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
) {
    val context = LocalContext.current
    SubcomposeAsyncImage(
        model = ImageRequest.Builder(context)
            .data(url)
            .crossfade(true)
            .build(),
        contentDescription = contentDescription,
        contentScale = contentScale,
        modifier = modifier,
        loading = { ShimmerBox() },
        error = { ErrorBox() },
    )
}

@Composable
fun ShimmerBox() {
    val infinite = rememberInfiniteTransition(label = "shimmer")
    val x by infinite.animateFloat(
        initialValue = -400f,
        targetValue = 1400f,
        animationSpec = infiniteRepeatable(
            animation = tween(1400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "shimmerX",
    )
    val brush = Brush.linearGradient(
        colors = listOf(
            PixoraColors.Surface,
            PixoraColors.GoldHaze,
            PixoraColors.Surface,
        ),
        start = Offset(x, 0f),
        end = Offset(x + 400f, 600f),
    )
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(brush),
    )
}

@Composable
private fun ErrorBox() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(PixoraColors.Surface2),
    )
}
