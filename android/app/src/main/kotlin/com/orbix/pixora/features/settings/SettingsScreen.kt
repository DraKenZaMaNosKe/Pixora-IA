package com.orbix.pixora.features.settings

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Ajustes screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun SettingsScreen() {
    FeatureShell(
        title = "Ajustes",
        icon = Icons.Outlined.Settings,
    )
}
