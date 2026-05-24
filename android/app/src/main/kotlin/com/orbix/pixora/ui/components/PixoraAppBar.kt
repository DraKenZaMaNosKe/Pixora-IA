package com.orbix.pixora.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PersonOutline
import androidx.compose.material3.Icon
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import android.app.Activity
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.orbix.pixora.data.auth.AuthService
import com.orbix.pixora.data.auth.PixoraUser
import com.orbix.pixora.data.auth.SignInResult
import com.orbix.pixora.data.credits.CreditService
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Pixora signature app bar — replaces every TopAppBar in the app.
 *
 * Anatomy (top to bottom):
 *   1. Thin iridescent ribbon (1px, gradient gold → aurora cyan → gold).
 *      Subtle but unmistakable Pixora brand mark on every screen.
 *   2. Eyebrow row: doc-code label (JetBrains Mono uppercase) + diamond
 *      pill showing CreditService.balance (always-visible 💎 N).
 *   3. Title row: Fraunces italic display with optional gold-gradient
 *      tint. Subtitle in Geist below if provided.
 *
 * Designed so EVERY section feels editorial + premium without each tab
 * having to reinvent its header. Per-section accent comes from the
 * `accentColor` parameter (drives the ribbon's middle stop).
 */
@Composable
fun PixoraAppBar(
    title: String,
    modifier: Modifier = Modifier,
    eyebrow: String? = null,
    subtitle: String? = null,
    accentColor: Color = PixoraColors.AuroraCyan,
    showCreditsPill: Boolean = true,
    showAvatar: Boolean = true,
    onAvatarClick: (() -> Unit)? = null,
    creditsViewModel: PixoraAppBarCreditsViewModel = hiltViewModel(),
    authViewModel: PixoraAppBarAuthViewModel = hiltViewModel(),
) {
    val balance by creditsViewModel.balance.collectAsStateWithLifecycle(initialValue = 0L)
    val user by authViewModel.user.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = context as? Activity

    // Inkwell Dark Solid (concept #1 from unified_header_darker_variants).
    // Warm carbon bg → no glow distractions → max contrast for the foil.
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(PixoraColors.InkwellWarm)
    ) {
        IridescentRibbon(accentColor)

        // Eyebrow row + avatar (left) + credits pill (right)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 8.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (showAvatar) {
                    AvatarRing(
                        user = user,
                        onClick = {
                            // External handler wins if provided. Otherwise:
                            // signed-in → sign-out via dropdown TBD;
                            // signed-out → trigger Credential Manager.
                            onAvatarClick?.invoke()
                                ?: activity?.let { authViewModel.signIn(it) }
                        },
                    )
                }
                Text(
                    text = eyebrow ?: "// PIXORA",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = PixoraColors.Gold.copy(alpha = 0.65f),
                    ),
                    maxLines = 1,
                )
            }
            if (showCreditsPill) DiamondPill(balance = balance)
        }

        // Title row — foil POP via dual gold tint on first word + cream rest.
        Text(
            text = buildAnnotatedString {
                val firstSpace = title.indexOf(' ')
                if (firstSpace > 0) {
                    withStyle(SpanStyle(color = PixoraColors.GoldBright)) {
                        append(title.substring(0, firstSpace))
                    }
                    withStyle(SpanStyle(color = PixoraColors.TextPrimary)) {
                        append(title.substring(firstSpace))
                    }
                } else {
                    withStyle(SpanStyle(color = PixoraColors.GoldBright)) {
                        append(title)
                    }
                }
            },
            style = MaterialTheme.typography.displayMedium.copy(fontStyle = FontStyle.Italic),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, bottom = if (subtitle == null) 14.dp else 4.dp),
        )

        if (subtitle != null) {
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall.copy(
                    color = PixoraColors.TextSecondary,
                ),
                maxLines = 2,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp),
            )
        }

        // Brass-gold hairline at 30% alpha — separates header from content
        // without competing visually. Per concept spec: "apenas separa".
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(0.6.dp)
                .background(PixoraColors.Gold.copy(alpha = 0.30f)),
        )
    }
}

/**
 * Foil ribbon — 2px iridescent gradient (gold → accent → gold). Sole
 * decorative stroke in the Inkwell Dark Solid header. Per concept #1:
 * "el foil es la única estrella en escena".
 */
@Composable
private fun IridescentRibbon(accent: Color) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(2.dp)
            .background(
                Brush.horizontalGradient(
                    colors = listOf(
                        PixoraColors.GoldDeep,
                        PixoraColors.Gold,
                        PixoraColors.GoldBright,
                        accent,
                        Color.White.copy(alpha = 0.85f),
                        accent,
                        PixoraColors.GoldBright,
                        PixoraColors.Gold,
                        PixoraColors.GoldDeep,
                    ),
                ),
            ),
    )
}

@Composable
private fun DiamondPill(balance: Long) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(
                Brush.horizontalGradient(
                    colors = listOf(
                        PixoraColors.GoldHaze,
                        PixoraColors.GoldDeep.copy(alpha = 0.3f),
                    ),
                ),
            )
            .padding(horizontal = 10.dp, vertical = 4.dp),
    ) {
        Text(
            text = "◆",
            color = PixoraColors.GoldBright,
            fontWeight = FontWeight.Bold,
            fontSize = MaterialTheme.typography.labelMedium.fontSize,
        )
        Text(
            text = " $balance",
            style = MaterialTheme.typography.labelMedium.copy(
                color = PixoraColors.GoldBright,
                fontFamily = PixoraFonts.JetBrainsMono,
                fontWeight = FontWeight.W600,
            ),
        )
    }
}

@Composable
private fun AvatarRing(user: PixoraUser?, onClick: () -> Unit) {
    val context = LocalContext.current
    Box(
        modifier = Modifier
            .size(36.dp)
            .shadow(elevation = 3.dp, shape = CircleShape)
            .clip(CircleShape)
            .background(PixoraColors.Surface)
            .border(
                width = 1.dp,
                color = PixoraColors.GoldBright.copy(alpha = 0.7f),
                shape = CircleShape,
            )
            .clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        val photo = user?.photoUrl
        if (photo != null) {
            AsyncImage(
                model = ImageRequest.Builder(context).data(photo).crossfade(true).build(),
                contentDescription = user.name ?: user.email ?: "Cuenta",
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            Icon(
                imageVector = Icons.Outlined.PersonOutline,
                contentDescription = "Iniciar sesión",
                tint = PixoraColors.GoldBright,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@HiltViewModel
class PixoraAppBarCreditsViewModel @Inject constructor(
    creditService: CreditService,
) : ViewModel() {
    val balance: Flow<Long> = creditService.balance
}

@HiltViewModel
class PixoraAppBarAuthViewModel @Inject constructor(
    private val authService: AuthService,
) : ViewModel() {
    val user: StateFlow<PixoraUser?> = authService.user

    fun signIn(activity: Activity) {
        viewModelScope.launch {
            val result = authService.signIn(activity)
            // Errors will be surfaced via snackbar once we wire one in the AppBar
            when (result) {
                is SignInResult.Success -> println("[Auth] Welcome ${result.user.name}")
                is SignInResult.Cancelled -> println("[Auth] cancelled: ${result.reason}")
                is SignInResult.Error -> println("[Auth] error: ${result.message}")
            }
        }
    }

    fun signOut() = authService.signOut()
}
