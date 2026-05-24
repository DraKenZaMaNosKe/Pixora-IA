package com.orbix.pixora.features.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Diamond
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.Workspaces
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts

private data class DeckItem(
    val key: String,            // "[ACT.001]" left bracket — looks like a system call number
    val title: String,
    val subtitle: String? = null,
    val icon: ImageVector,
    val accent: Color = PixoraColors.GoldBright,
    val action: String = "TAP",
)

private data class DeckSection(
    val label: String,
    val items: List<DeckItem>,
)

/**
 * Settings — "Control Deck HUD" (concept §19.2 v1.7.17). Reads as a
 * mission-control panel: ink background with cyan scanline borders,
 * JetBrains Mono uppercase section headers prefixed `//`, each row a
 * bracketed call number + icon + label + right-edge action chip.
 *
 * No theme picker — v2 ships with the single Pixora Cosmos theme
 * (Eduardo decision, see memory feedback_single_theme_v2). Section
 * order: ACCOUNT / CREDITS+SUBSCRIPTION / NOTIFICATIONS / ABOUT+LEGAL.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(viewModel: SettingsViewModel = hiltViewModel()) {
    val balance by viewModel.balance.collectAsStateWithLifecycle(initialValue = 0L)

    val sections = listOf(
        DeckSection(
            label = "// CUENTA",
            items = listOf(
                DeckItem(
                    key = "[ACT.001]",
                    title = "Iniciar sesión con Google",
                    subtitle = "Sincroniza favoritos + créditos en otros dispositivos",
                    icon = Icons.Outlined.AccountCircle,
                    accent = PixoraColors.AuroraCyan,
                    action = "LOGIN",
                ),
            ),
        ),
        DeckSection(
            label = "// CRÉDITOS Y SUSCRIPCIÓN",
            items = listOf(
                DeckItem(
                    key = "[CRD.001]",
                    title = "Mis diamantes",
                    subtitle = "Balance: $balance ◆ · ganas 1 ◆ cada anuncio visto",
                    icon = Icons.Outlined.Diamond,
                    accent = PixoraColors.GoldBright,
                    action = "VER",
                ),
                DeckItem(
                    key = "[SUB.001]",
                    title = "Pixora Premium",
                    subtitle = "Sin anuncios, descargas ilimitadas, acceso prioritario",
                    icon = Icons.Outlined.Star,
                    accent = PixoraColors.AuroraAmber,
                    action = "UPGRADE",
                ),
            ),
        ),
        DeckSection(
            label = "// NOTIFICACIONES",
            items = listOf(
                DeckItem(
                    key = "[NOT.001]",
                    title = "Avisos de contenido nuevo",
                    subtitle = "Te avisamos cuando subimos wallpapers o tonos nuevos",
                    icon = Icons.Outlined.NotificationsActive,
                    accent = PixoraColors.AuroraLavender,
                    action = "ON",
                ),
            ),
        ),
        DeckSection(
            label = "// ACERCA DE",
            items = listOf(
                DeckItem(
                    key = "[VER.001]",
                    title = "Pixora IA",
                    subtitle = "v2.0.0-alpha1 · Orbix Studio · Hecho en Guadalajara",
                    icon = Icons.Outlined.Workspaces,
                    accent = PixoraColors.GoldBright,
                    action = "INFO",
                ),
                DeckItem(
                    key = "[LEG.001]",
                    title = "Privacidad",
                    subtitle = "Cómo manejamos tus datos",
                    icon = Icons.Outlined.PrivacyTip,
                    accent = PixoraColors.AuroraCyan,
                    action = "READ",
                ),
                DeckItem(
                    key = "[LEG.002]",
                    title = "Términos de uso",
                    subtitle = "Léelos antes de aplicar wallpapers",
                    icon = Icons.Outlined.Description,
                    accent = PixoraColors.AuroraCyan,
                    action = "READ",
                ),
                DeckItem(
                    key = "[LIC.001]",
                    title = "Licencias open source",
                    subtitle = "Las librerías y créditos detrás de la app",
                    icon = Icons.Outlined.Info,
                    accent = PixoraColors.TextSecondary,
                    action = "VIEW",
                ),
            ),
        ),
    )

    Scaffold(
        containerColor = PixoraColors.Ink,
        topBar = {
            PixoraAppBar(
                title = "Control Deck",
                eyebrow = "// AJUSTES",
                subtitle = "Lo que controlas tú, lo controlas aquí",
                accentColor = PixoraColors.AuroraCyan,
            )
        },
    ) { innerPadding ->
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            sections.forEachIndexed { sIdx, section ->
                item { SectionHeader(section.label) }
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(PixoraColors.Surface)
                            .border(
                                width = 0.5.dp,
                                color = PixoraColors.AuroraCyan.copy(alpha = 0.2f),
                                shape = RoundedCornerShape(12.dp),
                            ),
                    ) {
                        section.items.forEachIndexed { idx, item ->
                            DeckRow(item)
                            if (idx < section.items.lastIndex) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(0.5.dp)
                                        .background(PixoraColors.AuroraCyan.copy(alpha = 0.1f)),
                                )
                            }
                        }
                    }
                }
                if (sIdx == 0) {
                    item { Spacer(Modifier.height(8.dp)) }
                }
                item { Spacer(Modifier.height(4.dp)) }
            }
            item {
                Spacer(Modifier.height(20.dp))
                FooterStamp()
                Spacer(Modifier.height(40.dp))
            }
        }
    }
}

@Composable
private fun SectionHeader(label: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 4.dp, top = 18.dp, bottom = 6.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium.copy(
                color = PixoraColors.GoldBright,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
        Box(
            modifier = Modifier
                .height(1.dp)
                .fillMaxWidth()
                .background(
                    Brush.horizontalGradient(
                        listOf(PixoraColors.GoldBright.copy(alpha = 0.5f), Color.Transparent),
                    ),
                ),
        )
    }
}

@Composable
private fun DeckRow(item: DeckItem) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable { /* TODO wire each row's specific action */ }
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        // Left: call number
        Text(
            text = item.key,
            style = MaterialTheme.typography.labelSmall.copy(
                color = item.accent.copy(alpha = 0.7f),
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W500,
            ),
            modifier = Modifier.padding(end = 10.dp),
        )
        // Icon in a tight monochrome circle
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(32.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(item.accent.copy(alpha = 0.12f))
                .border(
                    width = 0.5.dp,
                    color = item.accent.copy(alpha = 0.4f),
                    shape = RoundedCornerShape(8.dp),
                ),
        ) {
            Icon(
                imageVector = item.icon,
                contentDescription = null,
                tint = item.accent,
                modifier = Modifier.size(18.dp),
            )
        }
        // Text body
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp, end = 8.dp),
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyLarge.copy(
                    color = PixoraColors.TextPrimary,
                    fontWeight = FontWeight.W600,
                ),
                maxLines = 1,
            )
            if (item.subtitle != null) {
                Text(
                    text = item.subtitle,
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = PixoraColors.TextSecondary,
                        fontFamily = PixoraFonts.JetBrainsMono,
                    ),
                    maxLines = 2,
                )
            }
        }
        // Right: action chip
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .border(0.7.dp, item.accent.copy(alpha = 0.6f), RoundedCornerShape(50))
                .padding(horizontal = 8.dp, vertical = 3.dp),
        ) {
            Text(
                text = item.action,
                style = MaterialTheme.typography.labelSmall.copy(
                    color = item.accent,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
        }
    }
}

@Composable
private fun FooterStamp() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(
            text = "PIXORA · ORBIX STUDIO",
            style = MaterialTheme.typography.labelSmall.copy(
                color = PixoraColors.GoldBright,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W800,
            ),
        )
        Text(
            text = "Hecho con cariño desde Guadalajara, MX · MMXXVI",
            style = MaterialTheme.typography.labelSmall.copy(
                color = PixoraColors.TextFaint,
                fontFamily = PixoraFonts.JetBrainsMono,
            ),
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}
