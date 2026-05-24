package com.orbix.pixora.ui.components

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.orbix.pixora.ui.theme.PixoraColors
import kotlin.math.cos
import kotlin.math.sin

/**
 * Tilt parallax state — exposes normalized roll/pitch in [-1, 1].
 *
 * One sensor listener per screen (subscribe inside [rememberTiltState]).
 * Multiple [TiltImage] cards on the same screen share the same state
 * so we don't spawn N listeners.
 *
 * Uses TYPE_GAME_ROTATION_VECTOR — same data as v1's 3D · TILT mode,
 * smoothed by the OS. Roll = side-to-side, pitch = forward-back.
 */
class TiltState internal constructor() {
    private val _roll = mutableStateOf(0f)
    private val _pitch = mutableStateOf(0f)
    val roll: State<Float> = _roll
    val pitch: State<Float> = _pitch

    internal fun update(roll: Float, pitch: Float) {
        _roll.value = roll
        _pitch.value = pitch
    }
}

@Composable
fun rememberTiltState(): TiltState {
    val context = LocalContext.current
    val state = remember { TiltState() }
    DisposableEffect(Unit) {
        val sm = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sm?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            ?: sm?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        val listener = object : SensorEventListener {
            private val rot = FloatArray(9)
            private val orient = FloatArray(3)
            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(rot, event.values)
                SensorManager.getOrientation(rot, orient)
                // orient[0] azimuth, orient[1] pitch (-pi/2..pi/2), orient[2] roll (-pi..pi)
                val pitch = (orient[1] / (Math.PI.toFloat() / 4f)).coerceIn(-1f, 1f)
                val roll = (orient[2] / (Math.PI.toFloat() / 4f)).coerceIn(-1f, 1f)
                state.update(roll = roll, pitch = pitch)
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        if (sm != null && sensor != null) {
            sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        }
        onDispose {
            sm?.unregisterListener(listener)
        }
    }
    return state
}

/**
 * Image with tilt-driven parallax. Pans/zooms the underlying bitmap
 * based on shared [TiltState] from [rememberTiltState]. Use inside
 * cards or hero previews.
 *
 * @param maxShiftPx max horizontal/vertical translation in pixels at
 *  full tilt. ~40 reads nicely on phone-size cards; bump to ~120 on
 *  full-screen previews.
 */
@Composable
fun TiltImage(
    url: String,
    contentDescription: String,
    tilt: TiltState,
    modifier: Modifier = Modifier,
    maxShiftPx: Float = 40f,
    extraZoom: Float = 1.15f, // slight overscale so edges don't reveal
) {
    val context = LocalContext.current
    Box(
        modifier = modifier
            .clip(RectangleShape)
            .background(PixoraColors.Surface),
    ) {
        AsyncImage(
            model = ImageRequest.Builder(context).data(url).crossfade(true).build(),
            contentDescription = contentDescription,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    // Roll → x, pitch → y (inverted so leaning right pulls image left)
                    translationX = -tilt.roll.value * maxShiftPx
                    translationY = tilt.pitch.value * maxShiftPx
                    scaleX = extraZoom
                    scaleY = extraZoom
                },
        )
    }
}

@Suppress("unused")
private fun rad(deg: Float): Float = (deg * Math.PI / 180f).toFloat()

@Suppress("unused")
private fun pointOnCircle(angleRad: Float, radius: Float): Offset =
    Offset(cos(angleRad) * radius, sin(angleRad) * radius)
