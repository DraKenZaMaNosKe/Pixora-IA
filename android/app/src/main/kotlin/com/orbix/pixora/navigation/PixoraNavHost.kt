package com.orbix.pixora.navigation

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.orbix.pixora.features.aigenerate.AiGenerateScreen
import com.orbix.pixora.features.arcano.ArcanoScreen
import com.orbix.pixora.features.aura.AuraMiniPlayer
import com.orbix.pixora.features.aura.AuraScreen
import com.orbix.pixora.features.cultura.CulturaScreen
import com.orbix.pixora.features.daycycle.DayCycleScreen
import com.orbix.pixora.features.eventos.EventosScreen
import com.orbix.pixora.features.favorites.FavoritesScreen
import com.orbix.pixora.features.live.LiveScreen
import com.orbix.pixora.features.ringtones.RingtonesScreen
import com.orbix.pixora.features.settings.SettingsScreen
import com.orbix.pixora.features.stories.StoriesScreen
import com.orbix.pixora.features.threed.ThreeDScreen
import com.orbix.pixora.features.wallpapers.WallpaperDetailScreen
import com.orbix.pixora.features.wallpapers.WallpapersScreen
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts

/**
 * Top-level NavHost — single Activity, all features as Composables.
 *
 * Bottom bar is a horizontally-scrollable LazyRow with ALL 13 destinations
 * (matches v1's "Ember Reactive Nav"). The selected tab auto-scrolls into
 * view, gets a gold-haze pill background, and shows its accent color on the
 * icon/label.
 *
 * Hidden routes (wallpaper detail) auto-hide the bottom bar by checking
 * against the destinations list.
 */
@Composable
fun PixoraNavHost() {
    val navController = rememberNavController()
    val currentEntry by navController.currentBackStackEntryAsState()
    val currentRoute = currentEntry?.destination?.route

    val routesInBar = PixoraDestination.All.map { it.route }
    val showBottomBar = currentRoute in routesInBar

    Scaffold(
        containerColor = PixoraColors.Ink,
        bottomBar = {
            Column {
                AuraMiniPlayer()
                if (showBottomBar) {
                    PixoraEmberNav(
                        currentRoute = currentRoute,
                        onNavigate = { dest ->
                            navController.navigate(dest.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                    )
                }
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = PixoraDestination.Wallpapers.route,
            modifier = Modifier.padding(innerPadding),
        ) {
            composable(PixoraDestination.Wallpapers.route) {
                WallpapersScreen(
                    onWallpaperClick = { id ->
                        navController.navigate(PixoraDestination.wallpaperDetail(id))
                    },
                )
            }
            composable(
                route = PixoraDestination.WallpaperDetailRoute,
                arguments = listOf(navArgument("id") { type = NavType.StringType }),
            ) { backStackEntry ->
                val id = backStackEntry.arguments?.getString("id").orEmpty()
                WallpaperDetailScreen(
                    wallpaperId = id,
                    onBack = { navController.popBackStack() },
                )
            }
            composable(PixoraDestination.Live.route) { LiveScreen() }
            composable(PixoraDestination.ThreeD.route) { ThreeDScreen() }
            composable(PixoraDestination.Cultura.route) { CulturaScreen() }
            composable(PixoraDestination.Eventos.route) { EventosScreen() }
            composable(PixoraDestination.Aura.route) { AuraScreen() }
            composable(PixoraDestination.Arcano.route) { ArcanoScreen() }
            composable(PixoraDestination.Stories.route) { StoriesScreen() }
            composable(PixoraDestination.DayCycle.route) { DayCycleScreen() }
            composable(PixoraDestination.Ringtones.route) { RingtonesScreen() }
            composable(PixoraDestination.AiGenerate.route) { AiGenerateScreen() }
            composable(PixoraDestination.Favorites.route) { FavoritesScreen() }
            composable(PixoraDestination.Settings.route) { SettingsScreen() }
        }
    }
}

/**
 * Ember Reactive Nav — horizontal scrollable bar with all 13 tabs.
 *
 * Each tab is a clickable pill (icon + short label). Selected tab gets:
 *  - Gold-haze background pill
 *  - Accent-colored icon + label (its destination's accent)
 *  - Top hairline in accent color
 * Plus we auto-scroll so the selected tab is always visible.
 */
@Composable
private fun PixoraEmberNav(
    currentRoute: String?,
    onNavigate: (PixoraDestination) -> Unit,
) {
    val items = PixoraDestination.All
    val listState = rememberLazyListState()
    val selectedIndex = items.indexOfFirst { it.route == currentRoute }
        .takeIf { it >= 0 } ?: 0

    // Auto-scroll so the selected tab is visible (center if possible).
    LaunchedEffect(selectedIndex) {
        // Aim to land the selected tab around position 2 from the left edge,
        // so the user can see what's coming next.
        val target = (selectedIndex - 2).coerceAtLeast(0)
        listState.animateScrollToItem(target)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(PixoraColors.Ink2)
            // Respect the system 3-button / gesture nav so our tabs don't
            // sit under the OS chrome.
            .windowInsetsPadding(WindowInsets.navigationBars),
    ) {
        // Top hairline in gold-haze
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(
                    Brush.horizontalGradient(
                        listOf(Color.Transparent, PixoraColors.GoldHaze, Color.Transparent),
                    ),
                ),
        )
        LazyRow(
            state = listState,
            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            items(items, key = { it.route }) { dest ->
                NavTab(
                    dest = dest,
                    selected = dest.route == currentRoute,
                    onClick = { onNavigate(dest) },
                )
            }
        }
    }
}

@Composable
private fun NavTab(
    dest: PixoraDestination,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val iconColor by animateColorAsState(
        targetValue = if (selected) dest.accent else PixoraColors.TextSecondary,
        animationSpec = tween(180),
        label = "navIconColor",
    )
    val bgColor by animateColorAsState(
        targetValue = if (selected) PixoraColors.GoldHaze else Color.Transparent,
        animationSpec = tween(180),
        label = "navBgColor",
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .width(64.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(bgColor)
            .then(
                if (selected) Modifier.border(
                    width = 0.5.dp,
                    color = dest.accent.copy(alpha = 0.4f),
                    shape = RoundedCornerShape(14.dp),
                ) else Modifier
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            )
            .padding(vertical = 8.dp, horizontal = 4.dp),
    ) {
        Icon(
            imageVector = dest.icon,
            contentDescription = dest.label,
            tint = iconColor,
            modifier = Modifier.size(22.dp),
        )
        Text(
            text = dest.shortLabel,
            style = MaterialTheme.typography.labelSmall.copy(
                color = iconColor,
                fontFamily = PixoraFonts.JetBrainsMono,
            ),
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}
