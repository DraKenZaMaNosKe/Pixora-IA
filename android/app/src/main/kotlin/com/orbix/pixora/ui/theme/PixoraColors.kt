package com.orbix.pixora.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Pixora "Cosmos" palette — unified extract of the three v1 design systems
 * that survived: deep ink starfield base, gold premium accents, plus an
 * Aurora palette used to color-code AURA tracks and category badges.
 *
 * Hex values match the docs/design HTML redesign concepts so the Compose
 * implementation lines up 1:1 with the visual specs.
 */
object PixoraColors {

    // ─── Ink / Surfaces ───────────────────────────────────────────────
    val Ink = Color(0xFF070710)         // app background — deep cosmos
    val Ink2 = Color(0xFF0D0D18)        // surface layer 1 — sheets, modals
    val Surface = Color(0xFF14141F)     // cards / tiles
    val Surface2 = Color(0xFF1C1C2A)    // elevated cards (Pack header, etc.)
    val Hairline = Color(0x0FFFFFFF)    // 6% white — divider, border

    // Legacy aliases (keep so we don't break refs while migrating)
    val Dark get() = Ink
    val InkLayer get() = Ink2
    val InkTile get() = Surface

    // ─── Brand Gold ───────────────────────────────────────────────────
    val Gold = Color(0xFFD4AF37)         // primary brand gold
    val GoldBright = Color(0xFFF5D676)   // hover / focus / highlight
    val GoldDeep = Color(0xFF8B7228)     // labels, lowlight gold
    val GoldHaze = Color(0x1AD4AF37)     // 10% gold tint — glow background

    // Legacy alias
    val Copper get() = GoldDeep

    // ─── Aurora — used by AURA tracks + secondary category badges ─────
    val AuroraLavender = Color(0xFFB8A8E8)
    val AuroraOcean = Color(0xFF87C5E8)
    val AuroraMagenta = Color(0xFFC75FA8)
    val AuroraCyan = Color(0xFF4FC3D9)
    val AuroraPeach = Color(0xFFFFC7B5)
    val AuroraViolet = Color(0xFF6A4FB5)
    val AuroraAmber = Color(0xFFE8B86E)
    val AuroraRose = Color(0xFFE8A5C5)

    // ─── iOS callout greens/pinks (legacy compatibility) ──────────────
    val Cyan = AuroraCyan
    val PinkAccent = AuroraRose
    val RoseGold = AuroraPeach

    // ─── Status ───────────────────────────────────────────────────────
    val OkGreen = Color(0xFF10B981)
    val WarnAmber = Color(0xFFFFB300)
    val ErrorRed = Color(0xFFE5484D)

    // ─── Text — cream-not-white for editorial warmth ──────────────────
    val TextPrimary = Color(0xFFF5F4EE)     // cream
    val TextSecondary = Color(0xFF9A988E)   // dim cream
    val TextFaint = Color(0xFF5A5752)       // very dim — captions, metadata
    val TextDim = TextSecondary             // alias

    // ─── Dividers / borders ───────────────────────────────────────────
    val Divider = Color(0xFF2A2A3A)
}
