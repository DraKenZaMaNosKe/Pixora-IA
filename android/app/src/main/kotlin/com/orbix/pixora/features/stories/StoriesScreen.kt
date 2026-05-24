package com.orbix.pixora.features.stories

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoStories
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Historias screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun StoriesScreen() {
    FeatureShell(
        title = "Historias",
        icon = Icons.Outlined.AutoStories,
    )
}
