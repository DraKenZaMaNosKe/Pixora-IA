package com.orbix.pixora.features.live

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Live Wallpapers screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun LiveScreen() {
    FeatureShell(
        title = "Live Wallpapers",
        icon = Icons.Outlined.Movie,
    )
}
