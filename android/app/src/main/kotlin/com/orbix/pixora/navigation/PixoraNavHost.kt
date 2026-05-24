package com.orbix.pixora.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
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
import kotlinx.coroutines.launch

/**
 * Top-level NavHost — single Activity, all features as Composables.
 *
 * Bottom bar shows 4 primary tabs (Wall / Live / AURA / Favs) plus a
 * "Más" entry that opens a [ModalBottomSheet] with the 9 secondary
 * sections in a 3-col grid. This matches v1's _EmberReactiveNav idea
 * of giving access to ALL sections without cramming 13 tiny tabs.
 *
 * Hidden routes (wallpaper detail, future detail screens) auto-hide the
 * bottom bar by checking [PixoraDestination.Primary] / Secondary lists.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PixoraNavHost() {
    val navController = rememberNavController()
    val currentEntry by navController.currentBackStackEntryAsState()
    val currentRoute = currentEntry?.destination?.route

    // "Más" sheet state
    var showMoreSheet by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    // Hide bottom bar on full-bleed sub-routes (detail viewer, etc.).
    val routesInBar = PixoraDestination.Primary.map { it.route } +
        PixoraDestination.Secondary.map { it.route }
    val showBottomBar = currentRoute in routesInBar

    Scaffold(
        containerColor = PixoraColors.Ink,
        bottomBar = {
            Column {
                AuraMiniPlayer()
                if (showBottomBar) {
                    PixoraBottomBar(
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
                        onMoreClick = { showMoreSheet = true },
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

        if (showMoreSheet) {
            ModalBottomSheet(
                onDismissRequest = { showMoreSheet = false },
                sheetState = sheetState,
                containerColor = PixoraColors.Ink2,
            ) {
                MoreSheetContent(
                    onSectionClick = { dest ->
                        scope.launch {
                            sheetState.hide()
                            showMoreSheet = false
                        }
                        navController.navigate(dest.route) {
                            launchSingleTop = true
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun PixoraBottomBar(
    currentRoute: String?,
    onNavigate: (PixoraDestination) -> Unit,
    onMoreClick: () -> Unit,
) {
    NavigationBar(
        containerColor = PixoraColors.Ink2,
        contentColor = PixoraColors.TextPrimary,
    ) {
        PixoraDestination.Primary.forEach { dest ->
            val selected = currentRoute == dest.route
            NavigationBarItem(
                selected = selected,
                onClick = { if (!selected) onNavigate(dest) },
                icon = { Icon(dest.icon, contentDescription = dest.label) },
                label = { Text(dest.label) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = PixoraColors.GoldBright,
                    selectedTextColor = PixoraColors.GoldBright,
                    indicatorColor = PixoraColors.GoldHaze,
                    unselectedIconColor = PixoraColors.TextSecondary,
                    unselectedTextColor = PixoraColors.TextSecondary,
                ),
            )
        }
        // "Más" entry — opens the secondary sections sheet.
        NavigationBarItem(
            selected = false,
            onClick = onMoreClick,
            icon = { Icon(PixoraDestination.MoreIcon, contentDescription = PixoraDestination.MoreLabel) },
            label = { Text(PixoraDestination.MoreLabel) },
            colors = NavigationBarItemDefaults.colors(
                unselectedIconColor = PixoraColors.TextSecondary,
                unselectedTextColor = PixoraColors.TextSecondary,
                indicatorColor = PixoraColors.GoldHaze,
            ),
        )
    }
}

@Composable
private fun MoreSheetContent(onSectionClick: (PixoraDestination) -> Unit) {
    Column(modifier = Modifier.padding(bottom = 24.dp)) {
        Text(
            text = "// PIXORA · SECCIONES",
            style = MaterialTheme.typography.labelSmall.copy(color = PixoraColors.GoldDeep),
            modifier = Modifier.padding(start = 20.dp, top = 4.dp, bottom = 8.dp),
        )
        Text(
            text = "Explora",
            style = MaterialTheme.typography.displaySmall.copy(
                color = PixoraColors.TextPrimary,
                fontStyle = FontStyle.Italic,
            ),
            modifier = Modifier.padding(start = 20.dp, bottom = 16.dp),
        )
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            contentPadding = PaddingValues(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            items(PixoraDestination.Secondary) { dest ->
                SectionTile(dest, onClick = { onSectionClick(dest) })
            }
        }
    }
}

@Composable
private fun SectionTile(dest: PixoraDestination, onClick: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clip(RoundedCornerShape(14.dp))
            .background(PixoraColors.Surface)
            .clickable { onClick() }
            .padding(vertical = 18.dp, horizontal = 8.dp)
            .fillMaxWidth(),
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(PixoraColors.GoldHaze),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = dest.icon,
                contentDescription = dest.label,
                tint = PixoraColors.GoldBright,
                modifier = Modifier.size(24.dp),
            )
        }
        Text(
            text = dest.label,
            style = MaterialTheme.typography.labelMedium.copy(color = PixoraColors.TextPrimary),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 10.dp),
        )
    }
}
