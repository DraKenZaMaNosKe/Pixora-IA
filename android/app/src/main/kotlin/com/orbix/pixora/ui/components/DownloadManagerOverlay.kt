package com.orbix.pixora.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Wallpaper
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts

/**
 * Stages the apply pipeline goes through. Caller drives them as state
 * changes — overlay never advances on its own.
 */
enum class DownloadStage {
    Idle,           // hidden
    Downloading,    // bitmap fetch
    Applying,       // WallpaperManager call
    Success,        // 1.5s celebration before auto-dismiss
    Error,          // shown until user dismisses
}

/**
 * Full-screen blocking overlay that shows what's happening during a
 * download + apply pipeline. Replaces the silent "press button, wait,
 * snackbar appears" UX with a celebratory visual sequence.
 *
 * Aesthetic: dimmed scrim + center card with rotating gold halo + stage
 * icon + label + optional progress bar. JetBrains Mono everywhere for
 * the "tactical / mission control" feel that matches the HUD viewer.
 *
 * Auto-dismiss: caller sets stage back to Idle in onDismissed() callback.
 */
@Composable
fun DownloadManagerOverlay(
    stage: DownloadStage,
    progress: Float = -1f, // -1 = indeterminate
    errorMessage: String? = null,
    modifier: Modifier = Modifier,
) {
    AnimatedVisibility(
        visible = stage != DownloadStage.Idle,
        enter = fadeIn(tween(200)),
        exit = fadeOut(tween(400)),
        modifier = modifier,
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xCC02050A)),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier
                    .padding(40.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(PixoraColors.Surface)
                    .border(
                        width = 1.dp,
                        color = PixoraColors.GoldBright.copy(alpha = 0.4f),
                        shape = RoundedCornerShape(16.dp),
                    )
                    .padding(32.dp),
            ) {
                StageHalo(stage)
                StageLabel(stage)
                if (progress in 0f..1f) ProgressBar(progress)
                if (stage == DownloadStage.Error && errorMessage != null) {
                    Text(
                        text = errorMessage,
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.bodySmall.copy(
                            color = PixoraColors.TextSecondary,
                        ),
                    )
                }
            }
        }
    }
}

@Composable
private fun StageHalo(stage: DownloadStage) {
    val infinite = rememberInfiniteTransition(label = "halo")
    val angle by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(2400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "haloAngle",
    )

    val (icon, color, animated) = when (stage) {
        DownloadStage.Downloading -> Triple(
            Icons.Outlined.CloudDownload, PixoraColors.AuroraCyan, true,
        )
        DownloadStage.Applying -> Triple(
            Icons.Outlined.Wallpaper, PixoraColors.GoldBright, true,
        )
        DownloadStage.Success -> Triple(
            Icons.Outlined.CheckCircle, Color(0xFF10D08C), false,
        )
        DownloadStage.Error -> Triple(
            Icons.Outlined.ErrorOutline, PixoraColors.Ruby, false,
        )
        else -> Triple(Icons.Outlined.CloudDownload, PixoraColors.GoldBright, false)
    }

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(108.dp),
    ) {
        // Outer rotating halo (only while in-flight)
        if (animated) {
            Box(
                modifier = Modifier
                    .size(108.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.sweepGradient(
                            0f to Color.Transparent,
                            0.25f to color.copy(alpha = 0.6f),
                            0.5f to Color.Transparent,
                            0.75f to color.copy(alpha = 0.3f),
                            1f to Color.Transparent,
                        ),
                    )
                    .rotateRing(angle),
            )
        }
        // Inner solid circle
        Box(
            modifier = Modifier
                .size(76.dp)
                .clip(CircleShape)
                .background(PixoraColors.Ink)
                .border(width = 1.dp, color = color.copy(alpha = 0.8f), shape = CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            CenterIcon(icon, color)
        }
    }
}

@Composable
private fun CenterIcon(icon: ImageVector, color: Color) {
    Icon(
        imageVector = icon,
        contentDescription = null,
        tint = color,
        modifier = Modifier.size(36.dp),
    )
}

@Composable
private fun StageLabel(stage: DownloadStage) {
    val (eyebrow, label) = when (stage) {
        DownloadStage.Downloading -> "// DOWNLOADING" to "Descargando obra…"
        DownloadStage.Applying -> "// APPLYING" to "Aplicando wallpaper…"
        DownloadStage.Success -> "// DONE" to "¡Listo!"
        DownloadStage.Error -> "// ERROR" to "Algo salió mal"
        else -> "" to ""
    }
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = eyebrow,
            style = MaterialTheme.typography.labelSmall.copy(
                color = PixoraColors.GoldDeep,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W600,
            ),
        )
        Spacer(Modifier.height(4.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.titleMedium.copy(
                color = PixoraColors.TextPrimary,
                fontWeight = FontWeight.W700,
            ),
        )
    }
}

@Composable
private fun ProgressBar(value: Float) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Box(
            modifier = Modifier
                .height(4.dp)
                .clip(RoundedCornerShape(50))
                .background(PixoraColors.GoldHaze)
                .fillMaxWidth(value.coerceIn(0f, 1f)),
        )
        Text(
            text = "${(value * 100).toInt()}%",
            style = MaterialTheme.typography.labelSmall.copy(
                color = PixoraColors.GoldBright,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
    }
}

private fun Modifier.rotateRing(angle: Float): Modifier = this.rotate(angle)
