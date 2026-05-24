package com.orbix.pixora.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest

/**
 * Generic auto-advancing + manually-swipeable carousel.
 *
 * Auto-advances every [autoAdvanceMs] but resets the timer whenever
 * the user manually swipes. Dots indicator at the bottom shows the
 * current page.
 */
@Composable
fun <T> HeroCarousel(
    items: List<T>,
    autoAdvanceMs: Long = 8_000,
    modifier: Modifier = Modifier,
    dotsActiveColor: Color = Color.White,
    dotsInactiveColor: Color = Color.White.copy(alpha = 0.3f),
    content: @Composable (T) -> Unit,
) {
    if (items.isEmpty()) return
    val pagerState = rememberPagerState(initialPage = 0) { items.size }

    // Auto-advance — restarts the timer every time the user scrolls
    LaunchedEffect(items.size) {
        snapshotFlow { pagerState.currentPage to pagerState.isScrollInProgress }
            .collectLatest { (_, scrolling) ->
                if (scrolling) return@collectLatest
                delay(autoAdvanceMs)
                val next = (pagerState.currentPage + 1) % items.size
                pagerState.animateScrollToPage(next)
            }
    }

    Box(modifier = modifier) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxWidth(),
        ) { page -> content(items[page]) }

        // Dots indicator — pinned to the bottom of the carousel area
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 6.dp),
        ) {
            repeat(items.size) { i ->
                val on = i == pagerState.currentPage
                Box(
                    modifier = Modifier
                        .height(6.dp)
                        .size(width = if (on) 18.dp else 6.dp, height = 6.dp)
                        .clip(RoundedCornerShape(50))
                        .background(if (on) dotsActiveColor else dotsInactiveColor),
                )
            }
        }
    }
}
