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
        subtitle = "Tarot, runas y oráculos cósmicos",
        bullets = listOf(
            "Tirada diaria de cartas (3 cartas: pasado / presente / futuro)",
            "Catálogo de las 22 arcanos mayores con interpretación",
            "Runas vikingas y oráculo zodiacal",
            "Wallpaper dinámico que cambia con tu carta del día",
        ),
    )
}
