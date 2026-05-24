package com.orbix.pixora.ui.theme

import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.googlefonts.Font
import androidx.compose.ui.text.googlefonts.GoogleFont
import com.orbix.pixora.R

/**
 * Google Fonts provider — downloads fonts at runtime from fonts.google.com
 * via the Google Play Services Font Provider (no bundled .ttf needed,
 * shared cache with other apps that use the same fonts).
 *
 * Cert hashes live in `res/values/font_certs.xml` (must exist) — they
 * authenticate that the requesting app is talking to the real provider.
 */
private val provider = GoogleFont.Provider(
    providerAuthority = "com.google.android.gms.fonts",
    providerPackage = "com.google.android.gms",
    certificates = R.array.com_google_android_gms_fonts_certs,
)

private fun googleFamily(name: String, vararg weights: FontWeight, italic: Boolean = false): FontFamily {
    val gFont = GoogleFont(name)
    return FontFamily(
        weights.map { Font(gFont, provider, weight = it, style = if (italic) FontStyle.Italic else FontStyle.Normal) }
    )
}

/**
 * Pixora font catalog — five families, each chosen for a specific job
 * in the design system. See PixoraTypography for which TextStyle uses what.
 */
object PixoraFonts {

    /** Body / UI default — Vercel's Geist sans. Crisp, modern, neutral. */
    val Geist: FontFamily = googleFamily(
        "Geist",
        FontWeight.W300, FontWeight.W400, FontWeight.W500, FontWeight.W600, FontWeight.W700, FontWeight.W800,
    )

    /** Display / hero titles — Fraunces serif italic. Editorial elegance. */
    val Fraunces: FontFamily = googleFamily(
        "Fraunces",
        FontWeight.W300, FontWeight.W400, FontWeight.W500, FontWeight.W600, FontWeight.W700, FontWeight.W800,
        italic = true,
    )

    /** Labels / metadata — JetBrains Mono. HUD / technical voice. */
    val JetBrainsMono: FontFamily = googleFamily(
        "JetBrains Mono",
        FontWeight.W400, FontWeight.W500, FontWeight.W600, FontWeight.W700,
    )

    /** Editorial emphasis — Cormorant Garamond italic. AURA descriptions. */
    val CormorantItalic: FontFamily = googleFamily(
        "Cormorant Garamond",
        FontWeight.W400, FontWeight.W500, FontWeight.W600,
        italic = true,
    )

    /** Ceremonial / Arcano uppercase — Cinzel roman caps. Reserve. */
    val Cinzel: FontFamily = googleFamily(
        "Cinzel",
        FontWeight.W400, FontWeight.W500, FontWeight.W600, FontWeight.W700, FontWeight.W800,
    )
}
