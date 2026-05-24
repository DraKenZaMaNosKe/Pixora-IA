package com.orbix.pixora

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.orbix.pixora.navigation.PixoraNavHost
import com.orbix.pixora.ui.theme.PixoraTheme
import dagger.hilt.android.AndroidEntryPoint

/**
 * Single activity entry point for Pixora v2.
 *
 * All UI is Compose — no Fragments, no XML layouts (besides splash theme).
 * v1's MainActivity (Flutter) was 749 LOC of MethodChannel handlers; that
 * code is preserved as `MainActivity.kt.flutter-backup` for reference as we
 * port the handlers to native services incrementally.
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Install the Android 12+ SplashScreen — keeps the system splash
        // visible until the Compose hierarchy is ready, no flashes.
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            PixoraTheme {
                PixoraNavHost()
            }
        }
    }
}
