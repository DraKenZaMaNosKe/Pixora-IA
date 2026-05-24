package com.orbix.pixora.features.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Diamond
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.Workspaces
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import com.orbix.pixora.ui.components.PixoraAppBar
import com.orbix.pixora.ui.theme.PixoraColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

private data class SettingItem(
    val title: String,
    val subtitle: String? = null,
    val icon: ImageVector,
    val accent: Color? = null,
)

private data class SettingSection(
    val label: String,
    val items: List<SettingItem>,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(viewModel: SettingsViewModel = hiltViewModel()) {
    val balance by viewModel.balance.collectAsStateWithLifecycle(initialValue = 0L)

    val sections = listOf(
        SettingSection(
            label = "Cuenta",
            items = listOf(
                SettingItem("Iniciar sesión con Google", "Sincroniza favoritos y créditos", Icons.Outlined.AccountCircle),
            ),
        ),
        SettingSection(
            label = "Créditos y suscripción",
            items = listOf(
                SettingItem(
                    title = "Mis diamantes",
                    subtitle = "Balance: $balance 💎 · gana 1 por anuncio visto",
                    icon = Icons.Outlined.Diamond,
                    accent = Color(0xFF7C4DFF),
                ),
                SettingItem("Pixora Premium", "Sin anuncios + acceso prioritario", Icons.Outlined.Star, Color(0xFFFFB300)),
            ),
        ),
        SettingSection(
            label = "Apariencia",
            items = listOf(
                SettingItem("Tema", "Sistema / Claro / Oscuro", Icons.Outlined.DarkMode),
                SettingItem("Notificaciones", "Recibe avisos de contenido nuevo", Icons.Outlined.NotificationsActive),
            ),
        ),
        SettingSection(
            label = "Acerca de",
            items = listOf(
                SettingItem("Pixora IA", "v2.0.0-alpha1 · Orbix Studio", Icons.Outlined.Workspaces),
                SettingItem("Privacidad", "Cómo manejamos tus datos", Icons.Outlined.PrivacyTip),
                SettingItem("Términos de uso", "Léelos antes de aplicar wallpapers", Icons.Outlined.Description),
                SettingItem("Licencias open source", null, Icons.Outlined.Info),
            ),
        ),
    )

    Scaffold(
        containerColor = PixoraColors.Ink,
        topBar = {
            PixoraAppBar(
                title = "Ajustes",
                eyebrow = "// CONTROL DECK",
                subtitle = "Cuenta, créditos y preferencias",
                accentColor = PixoraColors.AuroraCyan,
            )
        },
    ) { innerPadding ->
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            sections.forEach { section ->
                item {
                    Text(
                        text = section.label.uppercase(),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 4.dp, top = 16.dp, bottom = 6.dp),
                    )
                }
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant),
                    ) {
                        section.items.forEachIndexed { idx, item ->
                            SettingRow(item)
                            if (idx < section.items.lastIndex) {
                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outlineVariant,
                                    thickness = 0.5.dp,
                                    modifier = Modifier.padding(start = 56.dp),
                                )
                            }
                        }
                    }
                }
            }
            item { Spacer(Modifier.size(20.dp)) }
        }
    }
}

@Composable
private fun SettingRow(item: SettingItem) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable { /* TODO: wire when each setting gets implemented */ }
            .padding(horizontal = 14.dp, vertical = 14.dp),
    ) {
        Icon(
            imageVector = item.icon,
            contentDescription = null,
            tint = item.accent ?: MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(24.dp),
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 14.dp),
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (item.subtitle != null) {
                Text(
                    text = item.subtitle,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(RoundedCornerShape(50))
                .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)),
        )
    }
}
