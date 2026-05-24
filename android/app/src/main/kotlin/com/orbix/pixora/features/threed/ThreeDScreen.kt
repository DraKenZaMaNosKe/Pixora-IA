package com.orbix.pixora.features.threed

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Wallpapers 3D screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun ThreeDScreen() {
    FeatureShell(
        title = "Wallpapers 3D",
        icon = Icons.Outlined.ViewInAr,
        subtitle = "Shaders y escenas interactivas en tiempo real",
        bullets = listOf(
            "Black Hole, Solar System, Galaxia procedural",
            "Acuario interactivo (toca para alimentar a los peces)",
            "Bosque con luciérnagas reactivas al touch",
            "Shaders GLSL personalizables con tu color favorito",
        ),
    )
}
