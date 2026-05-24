package com.orbix.pixora.features.aigenerate

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Pixora IA screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun AiGenerateScreen() {
    FeatureShell(
        title = "Pixora IA",
        icon = Icons.Outlined.AutoAwesome,
    )
}
