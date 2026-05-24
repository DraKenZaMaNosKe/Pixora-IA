package com.orbix.pixora.features.wallpapers

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade

/**
 * Full-bleed wallpaper preview + Aplicar CTA. Reached via tap on a grid card.
 *
 * Layout decisions:
 *  - AsyncImage fills the whole screen (under top/bottom bars).
 *  - Top scrim hosts back button + name (status-bar inset aware).
 *  - Bottom scrim hosts the big Aplicar button (nav-bar inset aware).
 *  - Snackbar surfaces apply success/error.
 *
 * The `wallpaperId` arg is consumed by the ViewModel via SavedStateHandle.
 * It's accepted here for API symmetry with NavHost (so the route stays
 * readable at the wiring site).
 */
@Composable
fun WallpaperDetailScreen(
    @Suppress("UNUSED_PARAMETER") wallpaperId: String,
    onBack: () -> Unit,
    viewModel: WallpaperDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val snackHost = remember { SnackbarHostState() }
    val context = LocalContext.current

    // Surface one-shot events as snackbars.
    LaunchedEffect(state.event) {
        when (val e = state.event) {
            is DetailEvent.Toast -> {
                snackHost.showSnackbar(e.message)
                viewModel.consumeEvent()
            }
            null -> Unit
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackHost) },
        containerColor = Color.Black,
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                state.loading -> CircularProgressIndicator(
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.wallpaper == null -> Text(
                    text = state.errorMsg ?: "Sin datos",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> DetailContent(
                    state = state,
                    onBack = onBack,
                    onApply = { viewModel.apply() },
                    context = context,
                )
            }
        }
    }
}

@Composable
private fun DetailContent(
    state: WallpaperDetailUiState,
    onBack: () -> Unit,
    onApply: () -> Unit,
    context: android.content.Context,
) {
    val w = state.wallpaper ?: return

    Box(modifier = Modifier.fillMaxSize()) {
        // Full-bleed image
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(w.imageUrl)
                .crossfade(true)
                .build(),
            contentDescription = w.name,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )

        // Top gradient + back button + title
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(140.dp)
                .align(Alignment.TopCenter)
                .background(
                    Brush.verticalGradient(
                        colors = listOf(Color(0xCC000000), Color.Transparent),
                    ),
                ),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 8.dp, vertical = 4.dp),
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    imageVector = Icons.Outlined.ArrowBack,
                    contentDescription = "Volver",
                    tint = Color.White,
                )
            }
            Text(
                text = w.name,
                style = MaterialTheme.typography.titleLarge,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(horizontal = 12.dp),
            )
            Text(
                text = w.authorName,
                style = MaterialTheme.typography.bodyMedium,
                color = Color(0xCCFFFFFF),
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
            )
        }

        // Bottom gradient + Apply CTA
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp)
                .align(Alignment.BottomCenter)
                .background(
                    Brush.verticalGradient(
                        colors = listOf(Color.Transparent, Color(0xEE000000)),
                    ),
                ),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomCenter)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Button(
                onClick = onApply,
                enabled = !state.applying,
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
            ) {
                if (state.applying) {
                    CircularProgressIndicator(
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp,
                        modifier = Modifier.height(20.dp),
                    )
                    Spacer(Modifier.height(0.dp))
                    Text(
                        text = "  Aplicando…",
                        fontWeight = FontWeight.SemiBold,
                    )
                } else {
                    Text(
                        text = "Aplicar como wallpaper",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}
