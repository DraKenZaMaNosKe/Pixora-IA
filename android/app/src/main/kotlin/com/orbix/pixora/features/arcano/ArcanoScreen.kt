package com.orbix.pixora.features.arcano

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Arcano screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun ArcanoScreen() {
    FeatureShell(
        title = "Arcano",
        icon = Icons.Outlined.AutoAwesome,
    )
}
