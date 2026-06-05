package com.orbix.pixora.renderers

import android.graphics.Color
import android.graphics.Typeface

/**
 * One of 10 selectable HUD presets. Each defines a coherent identity:
 * clock typography + color, EQ style, and which monitor layout to draw
 * (gold rings, mini pills, hex LEDs, ascii lines, arc gauges, glass shards).
 *
 * The picker in Settings stores the string key in `pixora_live.hud_preset`;
 * default is "sacred" (the original Pixora gold rings + serif clock).
 */
enum class HudPreset(
    val key: String,
    val displayName: String,
    val displaySub: String,
    val clockFont: Typeface,
    val clockColor: Int,
    val clockSizeMult: Float,       // multiplier of base (default 0.18 of width)
    val clockLetterSpacing: Float,
    val clockGlowColor: Int,
    val clockGlowRadius: Float,
    val eqStyle: EqStyle,
    val eqPrimary: Int,
    val eqSecondary: Int,
    val eqTertiary: Int,            // optional 3rd gradient stop, or 0
    val hudStyle: HudStyle,
    val hudAccent: Int,
) {
    SACRED(
        key = "sacred",
        displayName = "Pixora Sacred",
        displaySub = "Brand · dorado cósmico",
        clockFont = Typeface.create(Typeface.SERIF, Typeface.ITALIC),
        clockColor = Color.parseColor("#E6B655"),
        clockSizeMult = 0.18f,
        clockLetterSpacing = 0.08f,
        clockGlowColor = Color.parseColor("#E6B655"),
        clockGlowRadius = 30f,
        eqStyle = EqStyle.GOLD_SEGMENTED,
        eqPrimary = Color.parseColor("#E6B655"),
        eqSecondary = Color.parseColor("#FFD23F"),
        eqTertiary = 0,
        hudStyle = HudStyle.GOLD_RINGS,
        hudAccent = Color.parseColor("#E6B655"),
    ),
    MODERN(
        key = "modern",
        displayName = "Modern Mono",
        displaySub = "iOS · Winamp mirror",
        clockFont = if (android.os.Build.VERSION.SDK_INT >= 28)
            Typeface.create(Typeface.SANS_SERIF, 100, false)
        else Typeface.SANS_SERIF,
        clockColor = Color.WHITE,
        clockSizeMult = 0.26f,
        clockLetterSpacing = -0.055f,
        clockGlowColor = Color.BLACK,
        clockGlowRadius = 20f,
        eqStyle = EqStyle.WINAMP_MIRROR,
        eqPrimary = Color.rgb(0x00, 0xFF, 0x41),
        eqSecondary = Color.rgb(0xFF, 0xFF, 0x00),
        eqTertiary = Color.rgb(0xFF, 0x15, 0x00),
        hudStyle = HudStyle.MINI_PILLS,
        hudAccent = Color.rgb(0x00, 0xFF, 0x41),
    ),
    GEMINI(
        key = "gemini",
        displayName = "Gemini Pulse",
        displaySub = "Google AI · dots",
        clockFont = if (android.os.Build.VERSION.SDK_INT >= 28)
            Typeface.create(Typeface.SANS_SERIF, 200, false)
        else Typeface.SANS_SERIF,
        clockColor = Color.WHITE,
        clockSizeMult = 0.20f,
        clockLetterSpacing = -0.03f,
        clockGlowColor = Color.BLACK,
        clockGlowRadius = 16f,
        eqStyle = EqStyle.GEMINI_DOTS,
        eqPrimary = Color.parseColor("#4285F4"),
        eqSecondary = Color.parseColor("#EA4335"),
        eqTertiary = Color.parseColor("#FBBC04"),
        hudStyle = HudStyle.PILLS_COLORED,
        hudAccent = Color.parseColor("#4285F4"),
    ),
    GROK(
        key = "grok",
        displayName = "Grok Spectrum",
        displaySub = "Bars vivos multi-color",
        clockFont = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD),
        clockColor = Color.WHITE,
        clockSizeMult = 0.16f,
        clockLetterSpacing = -0.04f,
        clockGlowColor = Color.BLACK,
        clockGlowRadius = 10f,
        eqStyle = EqStyle.GROK_SPECTRUM,
        eqPrimary = Color.parseColor("#00E5FF"),
        eqSecondary = Color.parseColor("#00FF85"),
        eqTertiary = Color.parseColor("#FF6B35"),
        hudStyle = HudStyle.HORIZONTAL_METERS,
        hudAccent = Color.parseColor("#00E5FF"),
    ),
    CRT(
        key = "crt",
        displayName = "CRT Terminal",
        displaySub = "Sci-fi cyan · scanlines",
        clockFont = Typeface.create("sans-serif-condensed", Typeface.BOLD),
        clockColor = Color.parseColor("#00E5FF"),
        clockSizeMult = 0.18f,
        clockLetterSpacing = 0.12f,
        clockGlowColor = Color.parseColor("#00E5FF"),
        clockGlowRadius = 24f,
        eqStyle = EqStyle.CRT_BARS,
        eqPrimary = Color.parseColor("#00E5FF"),
        eqSecondary = Color.parseColor("#00FFFF"),
        eqTertiary = 0,
        hudStyle = HudStyle.HEX_LEDS,
        hudAccent = Color.parseColor("#00E5FF"),
    ),
    RETRO(
        key = "retro",
        displayName = "Retro CRT",
        displaySub = "VT323 verde · hacker",
        clockFont = Typeface.MONOSPACE,
        clockColor = Color.rgb(0x00, 0xFF, 0x41),
        clockSizeMult = 0.22f,
        clockLetterSpacing = 0.18f,
        clockGlowColor = Color.rgb(0x00, 0xFF, 0x41),
        clockGlowRadius = 18f,
        eqStyle = EqStyle.WINAMP_MIRROR,
        eqPrimary = Color.rgb(0x00, 0xFF, 0x41),
        eqSecondary = Color.rgb(0xFF, 0xFF, 0x00),
        eqTertiary = Color.rgb(0xFF, 0x15, 0x00),
        hudStyle = HudStyle.ASCII_LINES,
        hudAccent = Color.rgb(0x00, 0xFF, 0x41),
    ),
    FLAME(
        key = "flame",
        displayName = "Flame Wisps",
        displaySub = "Llamas · primal",
        clockFont = Typeface.create(Typeface.SERIF, Typeface.BOLD),
        clockColor = Color.parseColor("#FFD700"),
        clockSizeMult = 0.18f,
        clockLetterSpacing = 0.06f,
        clockGlowColor = Color.parseColor("#FF4500"),
        clockGlowRadius = 30f,
        eqStyle = EqStyle.FLAME,
        eqPrimary = Color.parseColor("#FFD700"),
        eqSecondary = Color.parseColor("#FF8C00"),
        eqTertiary = Color.parseColor("#FF4500"),
        hudStyle = HudStyle.EMBER_PILLS,
        hudAccent = Color.parseColor("#FF8C00"),
    ),
    AURORA(
        key = "aurora",
        displayName = "Aurora Boreal",
        displaySub = "Cintas · cielo estrellado",
        clockFont = if (android.os.Build.VERSION.SDK_INT >= 28)
            Typeface.create(Typeface.SERIF, 300, false)
        else Typeface.SERIF,
        clockColor = Color.WHITE,
        clockSizeMult = 0.20f,
        clockLetterSpacing = 0.10f,
        clockGlowColor = Color.parseColor("#00FFAA"),
        clockGlowRadius = 28f,
        eqStyle = EqStyle.AURORA_RIBBONS,
        eqPrimary = Color.parseColor("#00FFAA"),
        eqSecondary = Color.parseColor("#00C2FF"),
        eqTertiary = Color.parseColor("#B83BCB"),
        hudStyle = HudStyle.ARC_GAUGES,
        hudAccent = Color.parseColor("#00FFAA"),
    ),
    CYBER(
        key = "cyber",
        displayName = "Cyber Glitch",
        displaySub = "Amarillo · RGB split",
        clockFont = Typeface.create("sans-serif-condensed", Typeface.BOLD),
        clockColor = Color.parseColor("#FCEE0A"),
        clockSizeMult = 0.18f,
        clockLetterSpacing = 0.10f,
        clockGlowColor = Color.parseColor("#FCEE0A"),
        clockGlowRadius = 22f,
        eqStyle = EqStyle.CYBER_GLITCH,
        eqPrimary = Color.parseColor("#FCEE0A"),
        eqSecondary = Color.parseColor("#FF003C"),
        eqTertiary = Color.parseColor("#00FFEA"),
        hudStyle = HudStyle.HEX_LEDS,
        hudAccent = Color.parseColor("#FCEE0A"),
    ),
    CRYSTAL(
        key = "crystal",
        displayName = "Light Crystal",
        displaySub = "Theme claro · prisma",
        clockFont = if (android.os.Build.VERSION.SDK_INT >= 28)
            Typeface.create(Typeface.SERIF, 300, false)
        else Typeface.SERIF,
        clockColor = Color.parseColor("#2A3548"),
        clockSizeMult = 0.22f,
        clockLetterSpacing = 0.10f,
        clockGlowColor = Color.parseColor("#FF6496"),
        clockGlowRadius = 8f,
        eqStyle = EqStyle.CRYSTAL_SHARDS,
        eqPrimary = Color.parseColor("#FF6496"),
        eqSecondary = Color.parseColor("#96C8FF"),
        eqTertiary = Color.WHITE,
        hudStyle = HudStyle.GLASS_SHARDS,
        hudAccent = Color.parseColor("#FF6496"),
    );

    companion object {
        fun fromKey(key: String?): HudPreset {
            if (key == null) return SACRED
            return entries.firstOrNull { it.key == key } ?: SACRED
        }
    }
}

enum class EqStyle {
    GOLD_SEGMENTED,    // current Pixora gold (existing implementation)
    WINAMP_MIRROR,     // green/yellow/red segments + mirror reflection below
    GEMINI_DOTS,       // 5 colored circles that pulse (no bars)
    GROK_SPECTRUM,     // gradient bars cyan→green→yellow→orange + mirror
    CRT_BARS,          // cyan bars + horizontal wave overlay
    FLAME,             // tapered bars like flames, taller in center, flicker
    AURORA_RIBBONS,    // soft glowing pill-shaped bars with aurora gradient
    CYBER_GLITCH,      // yellow bars with red/cyan RGB offset on peaks
    CRYSTAL_SHARDS,    // translucent prismatic bars with chromatic edges
}

enum class HudStyle {
    GOLD_RINGS,        // existing SystemRingsRenderer 3 circles vertical left
    MINI_PILLS,        // mini-pills top-right with green dots (MiniHudRenderer)
    PILLS_COLORED,     // pills with Google color dots
    HORIZONTAL_METERS, // bars + values stacked top-right
    HEX_LEDS,          // hexagonal LED cells with value inside
    ASCII_LINES,       // text "RAM [████░░] 67%" terminal-style
    EMBER_PILLS,       // glowing ember dots with fire colors
    ARC_GAUGES,        // small arc gauges with percentage in center
    GLASS_SHARDS,      // trapezoidal glass shards (light theme)
}
