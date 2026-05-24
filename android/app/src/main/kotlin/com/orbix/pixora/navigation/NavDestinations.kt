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
import androidx.compose.material.icons.outlined.PublicOff
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.orbix.pixora.ui.theme.PixoraColors

/**
 * Pixora v2 destinations. One per major feature area, mirroring v1's
 * Ember Reactive Nav order. iOS-only gating is GONE (Android-only project).
 *
 * 13 destinations live in a horizontally-scrollable bottom bar — same UX
 * pattern as v1.7.17. Use:
 *   - [route]: NavHost wiring
 *   - [label]: long label (used in AppBar / sheets)
 *   - [shortLabel]: 3-4 char uppercase nav label (matches v1)
 *   - [icon]: bottom-bar icon
 *   - [accent]: per-section accent color (drives AppBar ribbon + nav pill)
 */
enum class PixoraDestination(
    val route: String,
    val label: String,
    val shortLabel: String,
    val icon: ImageVector,
    val accent: Color,
) {
    Wallpapers("wallpapers", "Wallpapers", "WALL", Icons.Outlined.Image, PixoraColors.GoldBright),
    Live("live", "Live", "LIVE", Icons.Outlined.Movie, PixoraColors.AuroraMagenta),
    ThreeD("threed", "3D", "3D", Icons.Outlined.ViewInAr, PixoraColors.AuroraCyan),
    Cultura("cultura", "Cultura", "CULT", Icons.Outlined.PublicOff, PixoraColors.AuroraAmber),
    Eventos("eventos", "Eventos", "EVNT", Icons.Outlined.Event, PixoraColors.AuroraPeach),
    Aura("aura", "AURA", "AURA", Icons.Outlined.Headphones, PixoraColors.AuroraLavender),
    Arcano("arcano", "Arcano", "ARC", Icons.Outlined.AutoAwesome, PixoraColors.AuroraViolet),
    Stories("stories", "Historias", "STOR", Icons.Outlined.AutoStories, PixoraColors.AuroraAmber),
    DayCycle("daycycle", "Day Cycle", "DAY", Icons.Outlined.Cyclone, PixoraColors.AuroraOcean),
    Ringtones("ringtones", "Tonos", "TON", Icons.Outlined.MusicNote, PixoraColors.AuroraMagenta),
    AiGenerate("aigenerate", "Pixora IA", "IA", Icons.Outlined.AutoAwesome, PixoraColors.AuroraCyan),
    Favorites("favorites", "Favoritos", "FAV", Icons.Outlined.Favorite, PixoraColors.AuroraRose),
    Settings("settings", "Ajustes", "SET", Icons.Outlined.Settings, PixoraColors.AuroraCyan),
    ;

    companion object {
        /** All destinations in display order — feeds the horizontal scrollable bar. */
        val All: List<PixoraDestination> = entries

        // ── Sub-routes (with args) ───────────────────────────────────────
        // Detail viewer for a single wallpaper. Reached by tapping a card
        // in the grid. Hidden from the bottom bar.
        const val WallpaperDetailRoute = "wallpaper_detail/{id}"
        fun wallpaperDetail(id: String) = "wallpaper_detail/$id"

        // Wallpaper Explorer HUD full-screen modal (PageView). Reached by
        // tapping a CHIP in the WALLPAPERS section. Args:
        //  - category: filter name (or "all")
        //  - initialId: wallpaper to land on first (or "first")
        const val WallpaperExplorerRoute = "wallpaper_explorer/{category}/{initialId}"
        fun wallpaperExplorer(category: String?, initialId: String?) =
            "wallpaper_explorer/${category ?: "all"}/${initialId ?: "first"}"

        // Live wallpaper detail (Frosted Stage). Reached by tapping a LiveCard.
        const val LiveDetailRoute = "live_detail/{id}"
        fun liveDetail(id: String) = "live_detail/$id"

        // Ringtone pack detail (Cassette A/B Sides).
        const val RingtonePackRoute = "ringtone_pack/{packId}"
        fun ringtonePack(packId: String) = "ringtone_pack/$packId"
    }
}
