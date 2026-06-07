package com.orbix.pixora.renderers

import android.app.ActivityManager
import android.content.Context
import android.util.Log

/**
 * Device performance tier — drives adaptive rendering across the wallpaper
 * renderers so flagship users get full visual quality (heavy shadows, 30fps
 * always-on marquee) while mid- and low-end devices degrade gracefully
 * without lag.
 *
 * Detected once at engine creation via [get] and cached. Tier is based on
 * total RAM + [ActivityManager.isLowRamDevice], which correlates well with
 * GPU capability on real-world Android devices (mid-range Samsungs ship
 * with Mali GPUs that choke on per-frame setShadowLayer calls; flagships
 * use Adreno/Mali-G that handle them fine).
 *
 * Why this matters: see commit history for the 2026-06-06 perf overhaul.
 * Eduardo's Samsung (mid-range, 4-6 GB RAM, Mali) was dropping to ~15fps
 * because every frame issued 20+ [android.graphics.Paint.setShadowLayer]
 * calls, each forcing software rendering for that paint op. Tier-aware
 * shadow capping + per-bar shadow opt-out brought it back to 28-30fps.
 *
 * @property shadowMultiplier multiplier applied to ALL setShadowLayer
 *   radii across renderers (0.15 on LOW means a 50px shadow becomes
 *   ~8px — still visible, ~95% cheaper). 1.0 = full quality.
 * @property useBarShadow if false, EQ styles MUST skip per-bar
 *   setShadowLayer calls (Aurora, Gemini Dots). Only HIGH gets per-bar
 *   shadows — on MID/LOW the bars still look good without them.
 * @property useRingHaloFill if false, [SystemRingsRenderer] skips the
 *   soft fill glow behind the ring (expensive on Mali; arc + dashed
 *   circle still draw).
 * @property activeFrameDelay ms between frames when audio is playing
 *   AND wallpaper is visible. 33ms = ~30fps.
 * @property idleMarqueeFrameDelay ms between frames when no audio (idle
 *   marquee animating). The marquee wave is slow — 16fps looks fine and
 *   halves battery cost during the majority case (no music).
 */
enum class DeviceTier(
    val shadowMultiplier: Float,
    val useBarShadow: Boolean,
    val useRingHaloFill: Boolean,
    val activeFrameDelay: Long,
    val idleMarqueeFrameDelay: Long,
    /**
     * Number of EQ bars actually drawn (HIGH=32, MID=20, LOW=12). The FFT
     * processing always computes [PixoraWallpaperService.BAR_COUNT]=32 bands
     * (cheap), but draw loops on MID/LOW iterate only this many and downsample
     * by index. Each bar is wider so the EQ still fills the same width.
     * Big win: ~38% fewer rect draws on MID for the Sacred segmented path.
     */
    val visibleBars: Int,
    /**
     * If true, [com.orbix.pixora.renderers.ClockRenderer] caches HH:MM + its
     * shadow halo to a Bitmap regenerated only when the minute changes (or
     * preset/style/glow changes). Per-frame cost drops from "render serif
     * text with 50px shadowLayer" to "blit a pre-rendered bitmap". HUGE on
     * Mali — setShadowLayer on TextPaint is the single most expensive paint
     * op on mid-range GPUs. Only the :SS digit redraws each frame.
     */
    val useClockTextCache: Boolean,
    /**
     * Use `SurfaceHolder.lockHardwareCanvas()` instead of `lockCanvas()` when
     * acquiring the wallpaper draw surface. Hardware canvas runs bitmap blits
     * on the GPU (essentially free) — software canvas blits on CPU and can
     * spend 50-100ms per large bitmap on mid-range Mali. This was THE bottleneck
     * for canvas_scene wallpapers (Goku Genkidama: 137ms just for 2 layer blits
     * before this flag). Trade-off: some software-only paint ops (setShadowLayer
     * on text/arc, BlurMaskFilter) are SILENTLY IGNORED on hardware canvas. We
     * already pre-cache the heaviest case (clock HH:MM) so the visual loss is
     * limited to ring arc glow + a few preset accents. HIGH tier opts out to
     * keep maximum visual quality on flagships that can absorb software canvas.
     */
    val useHardwareCanvas: Boolean,
) {
    // visibleBars tuned 2026-06-06 post-hardware-canvas:
    //   LOW 24 (was 12), MID 32 (was 20), HIGH 32. Hardware canvas absorbed
    //   the bar draw cost so we can restore full density across the board.
    //   Eduardo's Samsung uses MID and was getting 7ms/frame at 20 bars
    //   → ~1ms more at 32 still fits the 33ms budget easily.
    LOW (shadowMultiplier = 0.15f, useBarShadow = false, useRingHaloFill = false, activeFrameDelay = 50L, idleMarqueeFrameDelay = 100L, visibleBars = 24, useClockTextCache = true, useHardwareCanvas = true),
    MID (shadowMultiplier = 0.40f, useBarShadow = false, useRingHaloFill = true,  activeFrameDelay = 33L, idleMarqueeFrameDelay = 60L,  visibleBars = 32, useClockTextCache = true, useHardwareCanvas = true),
    HIGH(shadowMultiplier = 1.00f, useBarShadow = true,  useRingHaloFill = true,  activeFrameDelay = 33L, idleMarqueeFrameDelay = 33L,  visibleBars = 32, useClockTextCache = false, useHardwareCanvas = false);

    companion object {
        private const val TAG = "PixoraDeviceTier"

        @Volatile private var cached: DeviceTier? = null

        /** Returns the cached tier or detects + caches it. Safe to call from
         *  any thread. */
        fun get(context: Context): DeviceTier {
            cached?.let { return it }
            return synchronized(this) {
                cached ?: detect(context).also {
                    cached = it
                    Log.i(TAG, "Device tier resolved: $it")
                }
            }
        }

        private fun detect(context: Context): DeviceTier {
            return try {
                val am = context.applicationContext
                    .getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    ?: return MID
                if (am.isLowRamDevice) {
                    Log.i(TAG, "isLowRamDevice=true → LOW tier")
                    return LOW
                }
                val mi = ActivityManager.MemoryInfo()
                am.getMemoryInfo(mi)
                val totalGB = mi.totalMem / (1024f * 1024f * 1024f)
                val tier = when {
                    totalGB < 3.5f -> LOW
                    totalGB < 7.0f -> MID
                    else -> HIGH
                }
                Log.i(TAG, "Total RAM=%.1f GB → %s tier".format(totalGB, tier))
                tier
            } catch (e: Exception) {
                Log.w(TAG, "Tier detection failed, defaulting to MID: ${e.message}")
                MID
            }
        }
    }
}
