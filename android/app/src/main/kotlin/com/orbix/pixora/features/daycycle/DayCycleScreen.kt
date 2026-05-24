package com.orbix.pixora.features.daycycle

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Cyclone
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Day Cycle screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun DayCycleScreen() {
    FeatureShell(
        title = "Day Cycle",
        icon = Icons.Outlined.Cyclone,
    )
}
