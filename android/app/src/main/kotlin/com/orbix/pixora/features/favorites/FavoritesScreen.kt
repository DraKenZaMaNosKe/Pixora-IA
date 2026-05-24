package com.orbix.pixora.features.favorites

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Favoritos screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun FavoritesScreen() {
    FeatureShell(
        title = "Favoritos",
        icon = Icons.Outlined.Favorite,
    )
}
