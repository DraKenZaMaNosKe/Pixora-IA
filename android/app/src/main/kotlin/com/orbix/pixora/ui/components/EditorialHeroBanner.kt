package com.orbix.pixora.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.orbix.pixora.ui.theme.PixoraColors
import com.orbix.pixora.ui.theme.PixoraFonts

/**
 * Editorial Magazine Cover hero banner.
 *
 * Layout (matches `hero_banner_epic_concepts.html` concept #4 — Vogue /
 * Apartamento style):
 *  - Tall card (~4:5) with featured wallpaper as cover bleed
 *  - Masthead bar top: "PIXORA" (gold) + "VOL XII · 042" (mono)
 *  - Gold hairline below masthead
 *  - Cover blurb top-right: "INSIDE" mono header + Cormorant italic blurb
 *  - Cover title bottom-left: 2-word DM-Serif-style italic
 *    (first word white, second word gold-bright)
 *  - Barcode bottom-left (white bars on gold frame)
 *  - "Explore" sticker bottom-right rotated -4deg, gold-bright on ink
 *
 * v2 uses Fraunces italic instead of DM Serif Display (we already load
 * Fraunces and they're visually similar). Cover image, title, and blurb
 * are caller-driven so the same component can render Pixora Daily,
 * curator picks, event banners, etc.
 */
@Composable
fun EditorialHeroBanner(
    imageUrl: String,
    titleWord1: String,
    titleWord2: String,
    volumeLabel: String = "VOL XII · 042",
    blurbHeader: String = "INSIDE",
    blurbText: String = "24 featured artworks curated this month",
    stickerLabel: String = "Explore",
    onCardTap: () -> Unit = {},
    onExploreTap: () -> Unit = onCardTap,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    Box(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(4f / 5f)
            .padding(horizontal = 12.dp)
            .shadow(elevation = 16.dp, shape = RoundedCornerShape(12.dp))
            .clip(RoundedCornerShape(12.dp))
            .border(
                width = 0.6.dp,
                brush = SolidColor(PixoraColors.Gold.copy(alpha = 0.5f)),
                shape = RoundedCornerShape(12.dp),
            )
            .background(PixoraColors.Surface)
            .clickable { onCardTap() },
    ) {
        // Cover image — fullbleed, crossfades when imageUrl changes (auto
        // rotation handled by caller via state hoisting).
        AnimatedContent(
            targetState = imageUrl,
            transitionSpec = {
                fadeIn(tween(700)) togetherWith fadeOut(tween(700))
            },
            label = "heroRotate",
        ) { url ->
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(url)
                    .crossfade(true)
                    .build(),
                contentDescription = "$titleWord1 $titleWord2",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }

        // Bottom scrim so the title reads — covers ~40% from the bottom
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp)
                .align(Alignment.BottomCenter)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color(0xCC000000)),
                    ),
                ),
        )

        // Top scrim — subtle, helps masthead readability without darkening cover
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(60.dp)
                .align(Alignment.TopCenter)
                .background(
                    Brush.verticalGradient(
                        listOf(Color(0x99000000), Color.Transparent),
                    ),
                ),
        )

        // Masthead row
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceBetween,
            modifier = Modifier
                .align(Alignment.TopStart)
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
        ) {
            Text(
                text = "PIXORA",
                style = MaterialTheme.typography.labelMedium.copy(
                    color = PixoraColors.GoldBright,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W800,
                ),
            )
            Text(
                text = volumeLabel,
                style = MaterialTheme.typography.labelSmall.copy(
                    color = Color.White.copy(alpha = 0.85f),
                    fontFamily = PixoraFonts.JetBrainsMono,
                ),
            )
        }
        // Gold hairline under masthead
        Box(
            modifier = Modifier
                .align(Alignment.TopStart)
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
                .padding(top = 32.dp)
                .height(0.6.dp)
                .background(PixoraColors.Gold.copy(alpha = 0.5f)),
        )

        // Cover blurb top-right
        Column(
            horizontalAlignment = Alignment.End,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 42.dp, end = 14.dp)
                .width(130.dp),
        ) {
            Text(
                text = blurbHeader,
                style = MaterialTheme.typography.labelSmall.copy(
                    color = PixoraColors.GoldBright,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W700,
                ),
            )
            Text(
                text = blurbText,
                textAlign = TextAlign.End,
                style = MaterialTheme.typography.bodySmall.copy(
                    color = Color.White.copy(alpha = 0.9f),
                    fontFamily = PixoraFonts.CormorantItalic,
                    fontStyle = FontStyle.Italic,
                ),
            )
        }

        // Cover title bottom-left (DM Serif italic style → Fraunces italic)
        Text(
            text = buildAnnotatedString {
                withStyle(SpanStyle(color = Color.White)) { append(titleWord1) }
                append("\n")
                withStyle(SpanStyle(color = PixoraColors.GoldBright)) { append(titleWord2) }
            },
            style = MaterialTheme.typography.displayMedium.copy(
                fontFamily = PixoraFonts.Fraunces,
                fontStyle = FontStyle.Italic,
                fontWeight = FontWeight.W400,
                fontSize = MaterialTheme.typography.displayMedium.fontSize,
            ),
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 14.dp, bottom = 56.dp, end = 14.dp),
        )

        // Barcode bottom-left
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 14.dp, bottom = 14.dp)
                .border(
                    width = 1.5.dp,
                    color = PixoraColors.GoldBright,
                    shape = RoundedCornerShape(2.dp),
                )
                .background(Color.Black)
                .padding(4.dp)
                .size(width = 56.dp, height = 26.dp),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        // Faux barcode — repeating vertical white bars
                        Brush.horizontalGradient(
                            colorStops = arrayOf(
                                0f to Color.White, 0.04f to Color.White,
                                0.05f to Color.Transparent, 0.09f to Color.Transparent,
                                0.10f to Color.White, 0.14f to Color.White,
                                0.15f to Color.Transparent, 0.22f to Color.Transparent,
                                0.23f to Color.White, 0.27f to Color.White,
                                0.28f to Color.Transparent, 0.33f to Color.Transparent,
                                0.34f to Color.White, 0.38f to Color.White,
                                0.39f to Color.Transparent, 0.46f to Color.Transparent,
                                0.47f to Color.White, 0.51f to Color.White,
                                0.52f to Color.Transparent, 0.58f to Color.Transparent,
                                0.59f to Color.White, 0.64f to Color.White,
                                0.65f to Color.Transparent, 0.72f to Color.Transparent,
                                0.73f to Color.White, 0.77f to Color.White,
                                0.78f to Color.Transparent, 0.85f to Color.Transparent,
                                0.86f to Color.White, 0.92f to Color.White,
                                0.93f to Color.Transparent, 1f to Color.Transparent,
                            ),
                        ),
                    ),
            )
        }

        // Explore sticker bottom-right (rotated -4°) — TAPPABLE: opens the
        // Wallpaper Explorer modal (different action than tapping the card).
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 14.dp, bottom = 14.dp)
                .rotate(-4f)
                .shadow(elevation = 6.dp, shape = RoundedCornerShape(4.dp))
                .clip(RoundedCornerShape(4.dp))
                .background(PixoraColors.GoldBright)
                .clickable { onExploreTap() }
                .padding(horizontal = 14.dp, vertical = 8.dp),
        ) {
            Text(
                text = stickerLabel.uppercase(),
                style = MaterialTheme.typography.labelMedium.copy(
                    color = PixoraColors.Ink,
                    fontFamily = PixoraFonts.JetBrainsMono,
                    fontWeight = FontWeight.W800,
                ),
            )
        }
    }
}
