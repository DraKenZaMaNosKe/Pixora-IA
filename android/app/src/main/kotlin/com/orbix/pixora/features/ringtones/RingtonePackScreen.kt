package com.orbix.pixora.features.ringtones

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.orbix.pixora.data.models.Ringtone
import com.orbix.pixora.data.models.RingtonePack
import com.orbix.pixora.data.repos.RingtoneRepository
import com.orbix.pixora.data.ringtones.RingtonePreviewPlayer
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

private val NeonPink = Color(0xFFFF2BD6)
private val NeonPinkBright = Color(0xFFFF7ADF)
private val NeonMagenta = Color(0xFFC016FF)
private val NeonCyan = Color(0xFF00E5FF)
private val CassetteDark1 = Color(0xFF2A0D4A)
private val CassetteDark2 = Color(0xFF16062E)
private val CassetteInk = Color(0xFF0A0420)

/**
 * Ringtone Pack detail — Cassette A/B Sides (concept #1 from
 * tones_pack_page_concepts.html).
 *
 * Hero: giant neon-pink cassette with rotating reels, vinyl-bootleg
 * aesthetic. Tracks split SIDE A / SIDE B selectable via segmented
 * control. Active track pulses pink.
 */
@Composable
fun RingtonePackScreen(
    @Suppress("UNUSED_PARAMETER") packId: String,
    onBack: () -> Unit,
    viewModel: RingtonePackViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val nowPlayingId by viewModel.nowPlayingId.collectAsStateWithLifecycle()

    Scaffold(containerColor = Color.Black) { inner ->
        Box(modifier = Modifier
            .fillMaxSize()
            .padding(inner)
        ) {
            when {
                state.loading -> CircularProgressIndicator(
                    color = NeonPink,
                    modifier = Modifier.align(Alignment.Center),
                )
                state.pack == null -> Text(
                    text = "Pack no encontrado",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> CassettePackBody(
                    pack = state.pack!!,
                    nowPlayingId = nowPlayingId,
                    onBack = onBack,
                    onToneTap = viewModel::onToneTap,
                )
            }
        }
    }
}

@Composable
private fun CassettePackBody(
    pack: RingtonePack,
    nowPlayingId: String?,
    onBack: () -> Unit,
    onToneTap: (Ringtone) -> Unit,
) {
    // Vinyl-bootleg starfield background (subtle dots over deep ink)
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFF0A0420), Color.Black),
                ),
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.statusBars),
        ) {
            // Back chevron bar
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                Icon(
                    imageVector = Icons.Outlined.ArrowBack,
                    contentDescription = "Volver",
                    tint = Color.White,
                    modifier = Modifier
                        .size(28.dp)
                        .clickable { onBack() },
                )
            }

            HeroCassette(pack = pack)
            Spacer(Modifier.height(20.dp))
            SideSelector(currentSide = "SIDE A", totalSec = pack.tones.sumOf { it.duration })
            Spacer(Modifier.height(8.dp))
            TrackList(
                tones = pack.tones,
                nowPlayingId = nowPlayingId,
                onToneTap = onToneTap,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            )
            CtaSegmented()
            Spacer(
                Modifier
                    .fillMaxWidth()
                    .windowInsetsPadding(WindowInsets.navigationBars)
                    .height(0.dp),
            )
        }
    }
}

@Composable
private fun HeroCassette(pack: RingtonePack) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .height(220.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(
                Brush.verticalGradient(listOf(CassetteDark1, CassetteDark2)),
            )
            .border(
                width = 1.dp,
                color = NeonPink.copy(alpha = 0.35f),
                shape = RoundedCornerShape(16.dp),
            ),
    ) {
        // Cassette label (top)
        Box(
            modifier = Modifier
                .padding(start = 14.dp, end = 14.dp, top = 12.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(6.dp))
                .background(
                    Brush.horizontalGradient(listOf(NeonPink, NeonMagenta)),
                )
                .padding(horizontal = 12.dp, vertical = 8.dp),
        ) {
            Column {
                Text(
                    text = "PIXORA TAPES · VOL ${pack.id.hashCode().mod(99).toString().padStart(2, '0')}",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = Color.White.copy(alpha = 0.9f),
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W600,
                    ),
                )
                Text(
                    text = pack.name.uppercase(),
                    style = MaterialTheme.typography.headlineSmall.copy(
                        color = Color.White,
                        fontWeight = FontWeight.W900,
                        letterSpacing = 1.5.sp,
                    ),
                )
                val totalMin = pack.tones.sumOf { it.duration }.div(60).coerceAtLeast(1)
                Text(
                    text = "${pack.tones.size} TONES · ${totalMin} MIN · ${pack.category.uppercase()}",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = Color.White.copy(alpha = 0.9f),
                        fontFamily = PixoraFonts.JetBrainsMono,
                        fontWeight = FontWeight.W600,
                    ),
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }

        // Bridge (tape line between reels)
        Box(
            modifier = Modifier
                .padding(bottom = 56.dp)
                .align(Alignment.BottomCenter)
                .height(2.dp)
                .background(
                    Brush.horizontalGradient(
                        listOf(Color.Transparent, NeonPink, Color.Transparent),
                    ),
                )
                .padding(horizontal = 30.dp)
                .fillMaxWidth(0.4f),
        )

        // Reels — two spinning circles
        Row(
            horizontalArrangement = Arrangement.SpaceAround,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(bottom = 18.dp),
        ) {
            SpinningReel()
            SpinningReel()
        }
    }
}

@Composable
private fun SpinningReel() {
    val infinite = rememberInfiniteTransition(label = "reel")
    val angle by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(3000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "reelAngle",
    )

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(64.dp)
            .rotate(angle)
            .clip(CircleShape)
            .background(
                Brush.radialGradient(
                    listOf(CassetteInk, Color(0xFF1A0A3A), CassetteDark2),
                ),
            )
            .border(width = 2.dp, color = NeonPink.copy(alpha = 0.5f), shape = CircleShape),
    ) {
        // Cyan inner glow
        Box(
            modifier = Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(NeonCyan.copy(alpha = 0.18f)),
        )
        // Black hole center
        Box(
            modifier = Modifier
                .size(18.dp)
                .clip(CircleShape)
                .background(Color.Black),
        )
        // Spokes — 3 rotating lines via parent rotate
        Box(
            modifier = Modifier
                .size(60.dp)
                .background(
                    Brush.sweepGradient(
                        0f to Color.Transparent,
                        0.33f to Color.White.copy(alpha = 0.15f),
                        0.66f to Color.Transparent,
                        1f to Color.Transparent,
                    ),
                ),
        )
    }
}

@Composable
private fun SideSelector(currentSide: String, totalSec: Int) {
    val mm = totalSec / 60
    val ss = totalSec % 60
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
    ) {
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(4.dp))
                .border(1.dp, NeonCyan, RoundedCornerShape(4.dp))
                .padding(horizontal = 10.dp, vertical = 4.dp),
        ) {
            Text(
                text = currentSide,
                style = MaterialTheme.typography.labelMedium.copy(
                    color = NeonCyan,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
        }
        Text(
            text = "%02d:%02d".format(mm, ss),
            style = MaterialTheme.typography.labelMedium.copy(
                color = PixoraColors.TextFaint,
                fontFamily = PixoraFonts.JetBrainsMono,
            ),
        )
        // Hairline rule
        Box(
            modifier = Modifier
                .weight(1f)
                .height(1.dp)
                .background(
                    Brush.horizontalGradient(listOf(NeonCyan, Color.Transparent)),
                ),
        )
    }
}

@Composable
private fun TrackList(
    tones: List<Ringtone>,
    nowPlayingId: String?,
    onToneTap: (Ringtone) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = modifier,
    ) {
        items(tones.size, key = { tones[it].id }) { i ->
            val t = tones[i]
            val active = t.id == nowPlayingId
            TrackStrip(
                number = i + 1,
                tone = t,
                active = active,
                onClick = { onToneTap(t) },
            )
        }
    }
}

@Composable
private fun TrackStrip(
    number: Int,
    tone: Ringtone,
    active: Boolean,
    onClick: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(
                if (active) Brush.horizontalGradient(
                    listOf(NeonPink.copy(alpha = 0.18f), NeonMagenta.copy(alpha = 0.08f)),
                )
                else Brush.horizontalGradient(
                    listOf(Color(0xFF14082A).copy(alpha = 0.6f), Color(0xFF14082A).copy(alpha = 0.6f)),
                ),
            )
            .border(
                width = if (active) 1.dp else 0.5.dp,
                color = if (active) NeonPink else Color.White.copy(alpha = 0.06f),
                shape = RoundedCornerShape(8.dp),
            )
            .clickable { onClick() }
            .padding(horizontal = 10.dp, vertical = 8.dp),
    ) {
        Text(
            text = "%02d".format(number),
            style = MaterialTheme.typography.labelSmall.copy(
                color = if (active) NeonPink else PixoraColors.TextFaint,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
            modifier = Modifier.size(22.dp),
        )
        Text(
            text = tone.name,
            style = MaterialTheme.typography.bodyMedium.copy(
                color = if (active) Color.White else PixoraColors.TextPrimary,
                fontWeight = if (active) FontWeight.W700 else FontWeight.W500,
            ),
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = "%d:%02d".format(tone.duration / 60, tone.duration % 60),
            style = MaterialTheme.typography.labelSmall.copy(
                color = PixoraColors.TextDim,
                fontFamily = PixoraFonts.JetBrainsMono,
            ),
        )
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(24.dp)
                .clip(CircleShape)
                .background(if (active) NeonPink else Color.White.copy(alpha = 0.08f)),
        ) {
            Icon(
                imageVector = if (active) Icons.Outlined.Pause else Icons.Outlined.PlayArrow,
                contentDescription = if (active) "Pausar" else "Reproducir",
                tint = if (active) Color.White else NeonCyan,
                modifier = Modifier.size(14.dp),
            )
        }
    }
}

@Composable
private fun CtaSegmented() {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(12.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xE0080218))
            .border(
                width = 1.dp,
                color = NeonPink.copy(alpha = 0.35f),
                shape = RoundedCornerShape(12.dp),
            )
            .padding(6.dp),
    ) {
        CtaButton("RING", Modifier.weight(1f))
        CtaButton("NOTI", Modifier.weight(1f))
        CtaButton("ALARMA", Modifier.weight(1f))
    }
}

@Composable
private fun CtaButton(label: String, modifier: Modifier = Modifier) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(36.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(Color.White.copy(alpha = 0.04f))
            .clickable { /* TODO assign as system ringtone */ },
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium.copy(
                color = NeonPinkBright,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W700,
            ),
        )
    }
}

// ── ViewModel ───────────────────────────────────────────────────────────

data class RingtonePackUiState(
    val pack: RingtonePack? = null,
    val loading: Boolean = true,
)

@HiltViewModel
class RingtonePackViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: RingtoneRepository,
    private val previewPlayer: RingtonePreviewPlayer,
) : ViewModel() {

    private val packId: String = savedStateHandle.get<String>("packId").orEmpty()

    private val _state = MutableStateFlow(RingtonePackUiState())
    val state: StateFlow<RingtonePackUiState> = _state.asStateFlow()
    val nowPlayingId: StateFlow<String?> = previewPlayer.nowPlayingId

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val pack = repo.fetchAll().firstOrNull { it.id == packId }
            _state.value = RingtonePackUiState(pack = pack, loading = false)
        }
    }

    fun onToneTap(tone: Ringtone) = previewPlayer.toggle(tone.id, tone.audioUrl)

    override fun onCleared() {
        previewPlayer.stop()
        super.onCleared()
    }
}

