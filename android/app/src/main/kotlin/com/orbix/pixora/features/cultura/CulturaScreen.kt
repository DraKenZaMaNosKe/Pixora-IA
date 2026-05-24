package com.orbix.pixora.features.cultura

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PublicOff
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Cultura screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun CulturaScreen() {
    FeatureShell(
        title = "Cultura",
        icon = Icons.Outlined.PublicOff,
    )
}
