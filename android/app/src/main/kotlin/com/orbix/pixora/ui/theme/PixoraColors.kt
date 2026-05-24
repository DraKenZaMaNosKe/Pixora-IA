package com.orbix.pixora.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Pixora HUD palette — ported from v1's `HudTokens.kt`.
 *
 * The HUD identity: dark cosmic background, gold accents (premium feel),
 * cyan/pink for callouts (Holographic Foil aesthetic from v1.7.17 redesign).
 *
 * Material 3 color slots are mapped in `PixoraTheme.kt` — these constants
 * are the raw palette referenced by both the theme and individual widgets
 * that need exact colors (e.g. accent rings on cards).
 */
object PixoraColors {
    // ─── Backgrounds ───────────────────────────────────────────────────
    val Dark = Color(0xFF07060E)       // app background
    val InkLayer = Color(0xFF0F0E1A)   // surface above bg
    val InkTile = Color(0xFF1A1A22)    // cards / tiles

    // ─── Brand accents ────────────────────────────────────────────────
    val Gold = Color(0xFFC8A05A)       // primary HUD gold
    val GoldBright = Color(0xFFE5B040) // hover / focus
    val Copper = Color(0xFFB87A3C)     // secondary gold

    // ─── Action / callout ─────────────────────────────────────────────
    val Cyan = Color(0xFF00E5FF)       // info, panoramic glow
    val PinkAccent = Color(0xFFFF80AB) // hot, premium, sexy
    val RoseGold = Color(0xFFFFB6C1)   // soft accent

    // ─── Status ───────────────────────────────────────────────────────
    val OkGreen = Color(0xFF00C853)
    val WarnAmber = Color(0xFFFFB300)
    val ErrorRed = Color(0xFFFF4757)

    // ─── Text ─────────────────────────────────────────────────────────
    val TextPrimary = Color(0xFFE8E8F0)
    val TextSecondary = Color(0xFF9DA3B4)
    val TextDim = Color(0xFF5A6075)

    // ─── Dividers / borders ───────────────────────────────────────────
    val Divider = Color(0xFF2A2A3A)
}
