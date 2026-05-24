package com.orbix.pixora.navigation

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import com.orbix.pixora.features.aura.AuraMiniPlayer
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.orbix.pixora.features.aigenerate.AiGenerateScreen
import com.orbix.pixora.features.arcano.ArcanoScreen
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

/**
 * Top-level NavHost — single Activity, all features as Composables.
 *
 * The bottom bar shows only [PixoraDestination.Primary] for now (5 tabs).
 * The remaining 8 destinations are reachable via routes (e.g. from Wallpapers
 * grid taps, Settings shortcuts, etc.) and will be wired up as we port
 * features from v1.
 */
@Composable
fun PixoraNavHost() {
    val navController = rememberNavController()
    val currentEntry by navController.currentBackStackEntryAsState()
    val currentRoute = currentEntry?.destination?.route

    // Hide bottom bar on full-bleed sub-routes (detail viewer, etc.).
    val showBottomBar = PixoraDestination.Primary.any { it.route == currentRoute }

    Scaffold(
        bottomBar = {
            // Mini-player sits ABOVE the bottom nav bar so it persists
            // across tab switches without blocking the nav.
            Column {
                AuraMiniPlayer()
                if (showBottomBar) {
                    NavigationBar {
                        PixoraDestination.Primary.forEach { dest ->
                            val selected = currentRoute == dest.route
                            NavigationBarItem(
                                selected = selected,
                                onClick = {
                                    if (!selected) {
                                        navController.navigate(dest.route) {
                                            popUpTo(navController.graph.findStartDestination().id) {
                                                saveState = true
                                            }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    }
                                },
                                icon = { androidx.compose.material3.Icon(dest.icon, contentDescription = dest.label) },
                                label = { Text(dest.label) },
                            )
                        }
                    }
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
