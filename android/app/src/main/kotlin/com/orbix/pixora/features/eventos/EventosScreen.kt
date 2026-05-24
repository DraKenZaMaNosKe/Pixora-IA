package com.orbix.pixora.features.eventos

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Event
import androidx.compose.runtime.Composable
import com.orbix.pixora.features.common.FeatureShell

/**
 * Eventos screen — MVP shell.
 * Will be replaced with the real implementation as we port from v1.
 */
@Composable
fun EventosScreen() {
    FeatureShell(
        title = "Eventos",
        icon = Icons.Outlined.Event,
        subtitle = "Calendario lunar y fechas cósmicas",
        bullets = listOf(
            "Calendario lunar con fases en tiempo real",
            "Eclipses, solsticios y equinoccios",
            "Días feriados de México con wallpaper temático",
            "Notificaciones de eventos astronómicos importantes",
        ),
    )
}
