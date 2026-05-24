package com.orbix.pixora.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.AutoStories
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Cyclone
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.material.icons.outlined.Headphones
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.PublicOff
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Pixora v2 destinations. One per major feature area, mirroring v1's
 * bottom navigation order. iOS-only gating is GONE (Android-only project).
 *
 * Use [route] for NavHost wiring; [label] + [icon] for the bottom bar.
 */
enum class PixoraDestination(
    val route: String,
    val label: String,
    val icon: ImageVector,
) {
    Wallpapers("wallpapers", "Wall", Icons.Outlined.Image),
    Live("live", "Live", Icons.Outlined.Movie),
    ThreeD("threed", "3D", Icons.Outlined.ViewInAr),
    Cultura("cultura", "Cultura", Icons.Outlined.PublicOff),
    Eventos("eventos", "Eventos", Icons.Outlined.Event),
    Aura("aura", "AURA", Icons.Outlined.Headphones),
    Arcano("arcano", "Arcano", Icons.Outlined.AutoAwesome),
    Stories("stories", "Stories", Icons.Outlined.AutoStories),
    DayCycle("daycycle", "Day", Icons.Outlined.Cyclone),
    Ringtones("ringtones", "Tonos", Icons.Outlined.MusicNote),
    AiGenerate("aigenerate", "IA", Icons.Outlined.AutoAwesome),
    Favorites("favorites", "Favs", Icons.Outlined.Favorite),
    Settings("settings", "Ajustes", Icons.Outlined.Settings),
    ;

    companion object {
        /**
         * Bottom-bar tabs (4 sections + the "Más" opener).
         *
         * "Más" is a sentinel — it doesn't navigate, instead it opens the
         * [PixoraNavHost] secondary-sections modal. Real navigation to
         * stories/tonos/daycycle/etc. happens FROM that sheet.
         */
        val Primary = listOf(Wallpapers, Live, Aura, Favorites)
        val MoreLabel = "Más"
        val MoreIcon = Icons.Outlined.GridView

        /** Sections shown inside the "Más" modal grid (in display order). */
        val Secondary = listOf(
            Stories, DayCycle, Ringtones, ThreeD,
            Cultura, Eventos, Arcano, AiGenerate, Settings,
        )

        // ── Sub-routes (with args) ───────────────────────────────────────
        // Detail viewer for a single wallpaper. Reached by tapping a card
        // in the grid. Hidden from the bottom bar.
        const val WallpaperDetailRoute = "wallpaper_detail/{id}"
        fun wallpaperDetail(id: String) = "wallpaper_detail/$id"
    }
}
