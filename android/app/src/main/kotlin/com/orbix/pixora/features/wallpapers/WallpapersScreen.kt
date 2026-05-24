package com.orbix.pixora.features.wallpapers

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Image
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Wallpapers screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun WallpapersScreen() {
    FeatureShell(
        title = "Wallpapers",
        icon = Icons.Outlined.Image,
    )
}
