package com.orbix.pixora.features.aura

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Headphones
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * AURA screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun AuraScreen() {
    FeatureShell(
        title = "AURA",
        icon = Icons.Outlined.Headphones,
    )
}
