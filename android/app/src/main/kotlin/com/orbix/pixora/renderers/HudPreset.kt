package com.orbix.pixora.renderers

import android.graphics.Color
import android.graphics.Typeface

/**
 * Selectable HUD preset. Slimmed 2026-06-06 from 10 → 4 presets so we can
 * polish + perf-tune each one deeply instead of spreading thin. The 4 kept
 * cover distinct visual identities:
 *
 *  - CLASICO (was SACRED) → brand gold + segmented bars + system rings
 *  - GROK    → vivid multi-color spectrum bars (cyan/green/orange)
 *  - CRT     → sci-fi cyan bars with horizontal scanline wave overlay
 *  - CYBER   → glitchy yellow bars with RGB-split offset on peaks
 *
 * The picker in Settings stores the string key in `pixora_live.hud_preset`;
 * default is "classic" (the original Pixora gold rings + serif clock).
 * Migration: legacy "sacred" string maps to CLASICO via [fromKey].
 *
 * @property showSystemHud when false, the wallpaper engine SKIPS drawing
 *   the battery indicator, system rings (RAM/disk), and HUD overlays. Only
 *   the clock + equalizer remain. Lets each preset commit to a focused look:
 *   CLASICO is the "info-dense" preset; the others are minimalist.
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
    val showSystemHud: Boolean,
    /** Clock horizontal alignment within drawWithPreset (non-CLASICO path).
     *  CENTER = drawn at surface centerX (CLASICO behavior).
     *  LEFT   = anchored to left margin (Grok mockup style).
     *  RIGHT  = anchored to right margin. */
    val clockAlign: android.graphics.Paint.Align = android.graphics.Paint.Align.CENTER,
    /** Fractional Y position of the clock baseline (0..1 of surface height).
     *  CLASICO uses 0.18; Grok mockup is higher at 0.12. */
    val clockYFrac: Float = 0.18f,
) {
    CLASICO(
        key = "classic",
        displayName = "Clásico",
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
        showSystemHud = true,
    ),
    GROK(
        key = "grok",
        displayName = "Grok Spectrum",
        displaySub = "Bars vivos multi-color",
        // Approximates Syncopate (techy condensed bold) without bundling a TTF.
        clockFont = Typeface.create("sans-serif-condensed", Typeface.BOLD),
        clockColor = Color.WHITE,
        clockSizeMult = 0.24f,            // bumped from 0.16 to match mockup #72
        clockLetterSpacing = -0.02f,
        clockGlowColor = Color.BLACK,
        clockGlowRadius = 8f,
        eqStyle = EqStyle.GROK_SPECTRUM,
        eqPrimary = Color.parseColor("#00E5FF"),
        eqSecondary = Color.parseColor("#00FF85"),
        eqTertiary = Color.parseColor("#FF6B35"),
        hudStyle = HudStyle.HORIZONTAL_METERS,
        hudAccent = Color.parseColor("#00E5FF"),
        showSystemHud = true,             // re-enabled — user wants bars visible
        clockAlign = android.graphics.Paint.Align.LEFT,
        clockYFrac = 0.16f,               // pushed down to clear Android status bar
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
        showSystemHud = false,
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
        showSystemHud = false,
    );

    companion object {
        /**
         * Resolve a preset by its stored key. Accepts legacy "sacred" string
         * (pre-2026-06-06 rename) and routes it to [CLASICO]. Unknown keys
         * fall back to [CLASICO] silently.
         */
        fun fromKey(key: String?): HudPreset {
            if (key == null) return CLASICO
            if (key == "sacred") return CLASICO  // migration
            return entries.firstOrNull { it.key == key } ?: CLASICO
        }
    }
}

enum class EqStyle {
    GOLD_SEGMENTED,    // CLASICO — segmented gold bars + gold mirror
    GROK_SPECTRUM,     // GROK — gradient bars cyan→green→yellow→orange + mirror
    CRT_BARS,          // CRT — cyan bars + horizontal sine wave overlay
    CYBER_GLITCH,      // CYBER — yellow bars with red/cyan RGB offset on peaks
}

enum class HudStyle {
    GOLD_RINGS,        // CLASICO — SystemRingsRenderer (3 rings vertical left)
    HORIZONTAL_METERS, // GROK — bars + values stacked top-right
    HEX_LEDS,          // CRT + CYBER — hexagonal LED cells with value inside
}
