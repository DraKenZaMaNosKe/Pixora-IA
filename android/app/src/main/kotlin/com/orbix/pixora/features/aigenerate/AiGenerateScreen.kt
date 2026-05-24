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
        subtitle = "Genera wallpapers únicos con IA",
        bullets = listOf(
            "Describe lo que quieres ver y lo generamos",
            "Estilos preset: anime, fotorealista, pixel art, vaporwave",
            "Edita prompts guardados y vuelve a generar variantes",
            "Cuesta 5 diamantes por imagen · gratis con Premium",
        ),
    )
}
