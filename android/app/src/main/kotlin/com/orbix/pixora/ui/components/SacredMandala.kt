package com.orbix.pixora.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Sacred Geometry Mandala — procedural per-frequency mandala drawn on
 * Compose Canvas. Matches v1's "Sacred Geometry Mandala" concept for
 * the AURA section (per doc maestro §19.2): every frequency gets a
 * unique pattern derived from its Hz value, plus the track's accent
 * color from `aura_tracks.color_hex`.
 *
 * Construction rules:
 *   - petalCount = (hz mod 12) + 6  → between 6 and 17 petals per Hz
 *   - radius     = ~95% of size
 *   - rotation   = slow continuous (12s loop)
 *   - if isPlaying, add a breathing pulse (alpha + 1.05× scale)
 *
 * Layers (inside-out): center dot, inner ring, petal ring, outer ring,
 * radial spokes. All strokes use [color] with descending alpha so the
 * mandala reads as a luminous mark, not a solid wheel.
 */
@Composable
fun SacredMandala(
    color: Color,
    hz: Int?,
    modifier: Modifier = Modifier,
    isPlaying: Boolean = false,
) {
    val petalCount = remember(hz) { ((hz ?: 432) % 12 + 6).coerceAtLeast(6) }

    val infinite = rememberInfiniteTransition(label = "mandala_$hz")
    val rotation by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(12_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "mandalaRot",
    )
    val pulse by infinite.animateFloat(
        initialValue = if (isPlaying) 0.7f else 1f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1400),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "mandalaPulse",
    )

    Canvas(modifier = modifier) {
        val cx = size.width / 2f
        val cy = size.height / 2f
        val r = (size.minDimension / 2f) * 0.92f
        val baseAlpha = if (isPlaying) pulse else 0.9f

        rotate(rotation, pivot = Offset(cx, cy)) {
            // Outer ring
            drawCircle(
                color = color.copy(alpha = 0.55f * baseAlpha),
                radius = r,
                center = Offset(cx, cy),
                style = Stroke(width = 1.2f),
            )
            // Inner ring (smaller)
            drawCircle(
                color = color.copy(alpha = 0.35f * baseAlpha),
                radius = r * 0.55f,
                center = Offset(cx, cy),
                style = Stroke(width = 1f),
            )
            // Radial spokes / petals
            for (i in 0 until petalCount) {
                val angle = (i.toFloat() / petalCount) * 2f * PI.toFloat()
                val x1 = cx + cos(angle) * r * 0.55f
                val y1 = cy + sin(angle) * r * 0.55f
                val x2 = cx + cos(angle) * r
                val y2 = cy + sin(angle) * r
                drawLine(
                    color = color.copy(alpha = 0.75f * baseAlpha),
                    start = Offset(x1, y1),
                    end = Offset(x2, y2),
                    strokeWidth = 1.2f,
                )
                // Petal dots at the rim
                drawCircle(
                    color = color.copy(alpha = 0.9f * baseAlpha),
                    radius = 1.6f,
                    center = Offset(x2, y2),
                )
            }
            // Inner star — pairs of crossing lines mod petalCount/2
            val half = (petalCount / 2).coerceAtLeast(3)
            for (i in 0 until half) {
                val angle = (i.toFloat() / half) * PI.toFloat()
                val x1 = cx + cos(angle) * r * 0.55f
                val y1 = cy + sin(angle) * r * 0.55f
                val x2 = cx - cos(angle) * r * 0.55f
                val y2 = cy - sin(angle) * r * 0.55f
                drawLine(
                    color = color.copy(alpha = 0.25f * baseAlpha),
                    start = Offset(x1, y1),
                    end = Offset(x2, y2),
                    strokeWidth = 0.8f,
                )
            }
            // Center halo + dot
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(color.copy(alpha = 0.45f * baseAlpha), Color.Transparent),
                    radius = r * 0.35f,
                ),
                radius = r * 0.35f,
                center = Offset(cx, cy),
            )
            drawCircle(
                color = color.copy(alpha = baseAlpha),
                radius = 2.8f,
                center = Offset(cx, cy),
            )
        }
    }
}
