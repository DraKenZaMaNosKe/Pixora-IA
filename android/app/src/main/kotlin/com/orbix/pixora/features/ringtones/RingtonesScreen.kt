package com.orbix.pixora.features.ringtones

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Ringtones screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun RingtonesScreen() {
    FeatureShell(
        title = "Ringtones",
        icon = Icons.Outlined.MusicNote,
    )
}
