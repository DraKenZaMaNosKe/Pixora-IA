package com.orbix.pixora.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Pixora typography — Material 3 type scale mapped to the 5-family
 * Pixora font system:
 *
 *   - displayLarge / displayMedium → Fraunces italic (editorial headers)
 *   - headlineLarge / headlineMedium → Geist W800 (UI titles)
 *   - titleLarge / titleMedium → Geist W700 / W600
 *   - bodyLarge / bodyMedium → Geist W400 (default body copy)
 *   - labelLarge / labelMedium / labelSmall → JetBrains Mono W500
 *     uppercase letter-spaced (HUD chips, badges, doc-codes)
 *
 * Specialty fonts (Cormorant italic, Cinzel) live as standalone helpers
 * inside their respective sections (AURA editorial copy, Arcano ceremonial)
 * because they don't map cleanly to a Material slot.
 */
val PixoraTypography = Typography(

    // ─── Display (Fraunces italic) — Section heroes ──────────────────
    displayLarge = TextStyle(
        fontFamily = PixoraFonts.Fraunces,
        fontWeight = FontWeight.W400,
        fontSize = 48.sp,
        lineHeight = 52.sp,
        letterSpacing = (-0.6).sp,
    ),
    displayMedium = TextStyle(
        fontFamily = PixoraFonts.Fraunces,
        fontWeight = FontWeight.W400,
        fontSize = 36.sp,
        lineHeight = 40.sp,
        letterSpacing = (-0.4).sp,
    ),
    displaySmall = TextStyle(
        fontFamily = PixoraFonts.Fraunces,
        fontWeight = FontWeight.W400,
        fontSize = 28.sp,
        lineHeight = 32.sp,
        letterSpacing = (-0.3).sp,
    ),

    // ─── Headline (Geist heavy) — Main UI titles ─────────────────────
    headlineLarge = TextStyle(
        fontFamily = PixoraFonts.Geist,
        fontWeight = FontWeight.W800,
        fontSize = 32.sp,
        lineHeight = 38.sp,
        letterSpacing = (-0.5).sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = PixoraFonts.Geist,
        fontWeight = FontWeight.W800,
        fontSize = 24.sp,
        lineHeight = 30.sp,
        letterSpacing = (-0.3).sp,
    ),
    headlineSmall = TextStyle(
        fontFamily = PixoraFonts.Geist,
        fontWeight = FontWeight.W700,
        fontSize = 20.sp,
        lineHeight = 26.sp,
        letterSpacing = (-0.2).sp,
    ),

    // ─── Title (Geist semi/bold) — Card titles ───────────────────────
    titleLarge = TextStyle(
        fontFamily = PixoraFonts.Geist,
        fontWeight = FontWeight.W700,
        fontSize = 18.sp,
        lineHeight = 24.sp,
        letterSpacing = (-0.1).sp,
    ),
    titleMedium = TextStyle(
        fontFamily = PixoraFonts.Geist,
        fontWeight = FontWeight.W600,
        fontSize = 15.sp,
        lineHeight = 22.sp,
        letterSpacing = 0.sp,
    ),
    titleSmall = TextStyle(
        fontFamily = PixoraFonts.Geist,
        fontWeight = FontWeight.W600,
        fontSize = 13.sp,
        lineHeight = 18.sp,
        letterSpacing = 0.sp,
    ),

    // ─── Body (Geist regular) ────────────────────────────────────────
    bodyLarge = TextStyle(
        fontFamily = PixoraFonts.Geist,
        fontWeight = FontWeight.W400,
        fontSize = 15.sp,
        lineHeight = 22.sp,
        letterSpacing = 0.1.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = PixoraFonts.Geist,
        fontWeight = FontWeight.W400,
        fontSize = 13.sp,
        lineHeight = 19.sp,
        letterSpacing = 0.1.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = PixoraFonts.Geist,
        fontWeight = FontWeight.W400,
        fontSize = 12.sp,
        lineHeight = 17.sp,
        letterSpacing = 0.2.sp,
    ),

    // ─── Label (JetBrains Mono uppercase) — Chips, badges, doc codes ─
    labelLarge = TextStyle(
        fontFamily = PixoraFonts.JetBrainsMono,
        fontWeight = FontWeight.W500,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 1.6.sp, // ~0.22em
    ),
    labelMedium = TextStyle(
        fontFamily = PixoraFonts.JetBrainsMono,
        fontWeight = FontWeight.W500,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        letterSpacing = 1.4.sp,
    ),
    labelSmall = TextStyle(
        fontFamily = PixoraFonts.JetBrainsMono,
        fontWeight = FontWeight.W500,
        fontSize = 10.sp,
        lineHeight = 13.sp,
        letterSpacing = 1.2.sp,
    ),
)
