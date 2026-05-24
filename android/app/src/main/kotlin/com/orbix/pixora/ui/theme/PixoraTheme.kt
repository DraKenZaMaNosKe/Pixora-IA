package com.orbix.pixora.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val DarkPixoraColorScheme = darkColorScheme(
    primary = PixoraColors.Gold,
    onPrimary = PixoraColors.Dark,
    primaryContainer = PixoraColors.Copper,
    onPrimaryContainer = PixoraColors.TextPrimary,

    secondary = PixoraColors.Cyan,
    onSecondary = PixoraColors.Dark,
    tertiary = PixoraColors.PinkAccent,
    onTertiary = PixoraColors.Dark,

    background = PixoraColors.Dark,
    onBackground = PixoraColors.TextPrimary,
    surface = PixoraColors.InkLayer,
    onSurface = PixoraColors.TextPrimary,
    surfaceVariant = PixoraColors.InkTile,
    onSurfaceVariant = PixoraColors.TextSecondary,

    error = PixoraColors.ErrorRed,
    onError = PixoraColors.TextPrimary,

    outline = PixoraColors.Divider,
    outlineVariant = PixoraColors.Divider,
)

// v1 was dark-only — we mirror that for v2. Light scheme exists as
// fallback for users with system "force light", but the HUD aesthetic
// only works dark.
private val LightPixoraColorScheme = lightColorScheme(
    primary = PixoraColors.Gold,
    secondary = PixoraColors.Cyan,
    tertiary = PixoraColors.PinkAccent,
    background = PixoraColors.Dark,
    surface = PixoraColors.InkLayer,
    onBackground = PixoraColors.TextPrimary,
    onSurface = PixoraColors.TextPrimary,
)

@Composable
fun PixoraTheme(
    darkTheme: Boolean = true,  // force dark — see comment above
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkPixoraColorScheme else LightPixoraColorScheme

    // Make status bar + nav bar transparent so PixoraNavHost can paint
    // edge-to-edge. The window background (set by Theme.Pixora style) is
    // pixora_dark so there's no flash.
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as android.app.Activity).window
            WindowCompat.setDecorFitsSystemWindows(window, false)
            val controller = WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = !darkTheme
            controller.isAppearanceLightNavigationBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = PixoraTypography,
        content = content,
    )
}
