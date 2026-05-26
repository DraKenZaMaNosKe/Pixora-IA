# Pixora Architecture Refactor Plan

**Started:** 2026-05-25
**Strategy:** Strangler Pattern por dominio (refactor incremental sin pausar features)

## Why now

After ~1.5 years of organic growth, several core files have become "spaghetti":
multiple capabilities mixed together, making every change require reading
through unrelated code to find the relevant block. This is normal accumulated
debt; the refactor pays it down without halting the product.

The trigger: extracting the panoramic-wallpaper engine as a reusable mechanism
proved difficult because the code is intertwined with 14 other capabilities
inside a single 1589-line file.

## Approach

- **Strangler pattern**: refactor file by file, one per session, with on-device
  validation before commit (same workflow we used for #4/#4b/#4c/#7).
- **Behavior preserved**: external observable behavior stays identical — no
  feature regression, only internal cleanup.
- **One blueprint emerges per phase**: each refactored module gets a short
  README so future devs (or future Claude sessions) can replicate the pattern.
- **No big bang**: avoid the trap of "stop everything to rewrite half the app."

## Phases (tentative — adjust after each)

| # | Target | LOC now | Goal |
|---|---|---|---|
| **1** | `PixoraWallpaperService.kt` → extract `PanoramicWallpaperRenderer` | 1589 | Reusable panoramic engine + thin orchestrator |
| 2 | `MainActivity.kt` → split MethodChannel handlers by capability | ~700 | One handler class per domain (wallpaper, ringtone, story, day cycle) |
| 3 | `home_page.dart` → unify `_pages`/`_titles`/`items` triplication | ~700 | Single source of truth for bottom-nav tabs |
| 4 | `auto_rotate_service` + `day_cycle` + `story` → `RotatingWallpaperService` base | dispersed | Shared download/cache/apply/schedule logic |
| 5 | Long pages (ringtones, settings) → extract private widgets to own files | varies | One widget per file |

---

# Phase 1: Extract PanoramicWallpaperRenderer

## Current state of `PixoraWallpaperService.kt`

The file mixes **15 capabilities** inside one `PixoraEngine` inner class:

| # | Capability | State fields | Methods (lines) |
|---|---|---|---|
| 1 | Panoramic scrolling | isPanoramic, panoramicBitmap, touchStartX, scrollOffsetPx, targetScrollPx, scrollVelocity | partial loadWallpaperImage, partial createScaledBitmap, partial onOffsetsChanged, partial drawFrame, partial onTouchEvent |
| 2 | Static wallpaper | wallpaperBitmap, scaledBitmap, scaleVersion, lastDecoded*, lastScaled* | loadWallpaperImage (502-816), createScaledBitmap (1001-1119), calculateInSampleSize |
| 3 | Video wallpaper | mediaPlayer, isVideoWallpaper, videoStarting, videoLock | startVideoWallpaper, stopVideoWallpaper, releaseMediaPlayerSafely |
| 4 | Frame scrub (Explore) | frameScrubRenderer, isFrameMode, frameScrubUpdateRunnable, isInteractive | parts of loadWallpaperImage + onTouchEvent |
| 5 | Canvas scenes | canvasSceneRenderer, isCanvasSceneMode | parts of loadWallpaperImage + drawFrame |
| 6 | Equalizer visualizer | equalizerRenderer | onAudioStarted, part of drawFrame |
| 7 | Overlays (clock/battery/rings/caption/branding) | clockRenderer, batteryIndicator, systemRings, captionOverlay, brandingLogo, brandingTick | loadOverlaySettings, parts of drawFrame |
| 8 | Effect renderers (rain/firefly/aquarium/jellyfish/bubble/friends) | 6 renderers + 3 mode booleans | parts of loadWallpaperImage + drawFrame |
| 9 | Touch trail | touchTrail | part of onTouchEvent + loadWallpaperImage |
| 10 | Gyro / parallax | SensorManager listener | registerGyroIfNeeded, unregisterGyro, onSensorChanged |
| 11 | Ad visibility (drop to idle) | idleMode | adVisibilityReceiver |
| 12 | Keyguard / screen state | — | keyguardReceiver |
| 13 | Prefs listener + wallpaper path broadcast | — | registerPrefsListener, wallpaperPathReceiver |
| 14 | Engine lifecycle glue | — | onCreate, onSurfaceChanged, onVisibilityChanged, onSurfaceDestroyed, onDestroy |
| 15 | Drawing loop | drawing, animationPhase | drawFrame (1357-1497), drawBackground, drawGlowEffects, updateRendererState, drawRunnable |

### Spaghetti hot-spots (3 mega-functions)

| Method | LOC | Smell |
|---|---|---|
| `loadWallpaperImage()` | 314 (502-816) | One method deciding which mode based on path heuristics (`path.contains("firefly")`, `path.contains("lofi_girl_rain")`, etc.) and configuring 6+ renderers |
| `drawFrame()` | 140 (1357-1497) | Paints all modes + overlays in a single loop, with mode-flag conditionals |
| `onTouchEvent()` | 76 (1281-1357) | 4 touch behaviors in one (panoramic scroll + frame scrub + canvas interactive + trail) |

## Target architecture

```
PixoraWallpaperService (orchestrator, ~250 LOC)
├── Engine lifecycle (onCreate, onSurfaceChanged, onVisibilityChanged, onDestroy)
├── PathDispatcher: reads SharedPreferences → decides which renderer is active
│                   (no more inline path.contains() heuristics)
└── Delegates to capability renderers:
    ├── PanoramicWallpaperRenderer  ←  EXTRAÍBLE como módulo reusable
    ├── StaticWallpaperRenderer        (could inherit from Panoramic with scroll disabled)
    ├── VideoWallpaperRenderer
    ├── FrameScrubModeRenderer
    ├── CanvasSceneModeRenderer        (already partially modular in renderers/)
    ├── OverlayCompositor              (clock + battery + rings + caption + branding)
    ├── EffectLayer                    (one of: rain | firefly | aquarium | jellyfish | bubble | friends)
    └── AudioReactiveLayer             (equalizer visualizer)
```

### Panoramic renderer — the public contract we want

```kotlin
/**
 * Renders a wide bitmap as a panoramic wallpaper that scrolls horizontally
 * in response to launcher offset changes. Designed to plug into any Android
 * WallpaperService.Engine — Pixora uses it via PixoraWallpaperService, but
 * any standalone Android app can copy this single file and use it.
 *
 * Usage:
 *   class MyEngine : WallpaperService.Engine() {
 *       private val pano = PanoramicWallpaperRenderer(context)
 *
 *       override fun onSurfaceChanged(holder, format, w, h) {
 *           pano.onSurfaceChanged(w, h)
 *       }
 *       override fun onOffsetsChanged(xOffset, ...) {
 *           pano.onOffsetsChanged(xOffset)
 *       }
 *       override fun onDestroy() {
 *           pano.release()
 *       }
 *
 *       fun applyWallpaper(path: String) {
 *           pano.loadFromFile(path) { drawNextFrame() }
 *       }
 *
 *       private fun drawNextFrame() {
 *           val canvas = surfaceHolder.lockCanvas() ?: return
 *           pano.drawOn(canvas)
 *           surfaceHolder.unlockCanvasAndPost(canvas)
 *       }
 *   }
 */
class PanoramicWallpaperRenderer(private val context: Context) {

    // Lifecycle
    fun onSurfaceChanged(width: Int, height: Int)
    fun release()

    // Wallpaper source
    fun loadFromFile(path: String, onReady: () -> Unit = {})

    // Scroll input from launcher
    fun onOffsetsChanged(xOffset: Float)

    // Render
    fun drawOn(canvas: Canvas)

    // Optional: query state
    val isPanoramic: Boolean
    val scrollRangePx: Int
}
```

**Properties of this contract:**
- Single responsibility: load, scale, scroll, draw a wide bitmap.
- No knowledge of overlays, video, audio, scenes — orchestrator composes those on top.
- All idempotency guards (lastDecoded, lastScaled, scaleVersion) live inside.
- Safe to call from main thread; bitmap decode + scale happen on bg thread.
- Self-cleans bitmaps on `release()`.

## Migration steps (next session)

1. **Create skeleton** `PanoramicWallpaperRenderer.kt` with the public contract above (no impl yet).
2. **Move pure panoramic state + methods** from `PixoraEngine`:
   - Fields: `isPanoramic`, `panoramicBitmap`, `scrollOffsetPx`, `targetScrollPx`, `scrollVelocity`, `scaleVersion`, `lastScaledForPath`, `lastScaledSurfaceW/H`, `bitmapLock`.
   - From `createScaledBitmap()`: the panoramic branch (lines ~1014-1037) and the version guard.
   - From `loadWallpaperImage()`: the bitmap decode block (after `if (!isVideo)` guard) + the idempotency guard for decode.
   - From `onOffsetsChanged()`: the panoramic scroll math.
   - From `drawFrame()`: the panoramic bitmap blit (`canvas.drawBitmap(panBmp, -scrollOffsetPx, 0f, paint)`).
3. **Replace inline calls** in `PixoraEngine` with delegation to `pano.method()`.
4. **Validate on device** (apply panoramic wallpaper, scroll home, check logcat for behavior parity).
5. **Document** as `docs/blueprints/panoramic_wallpaper.md` with the usage example above + minimal sample app.

## Definition of done — Phase 1

- [ ] `PanoramicWallpaperRenderer.kt` exists with ~200 LOC, self-contained.
- [ ] `PixoraWallpaperService.kt` shrinks to ~1400 LOC (loses ~190 LOC of panoramic logic).
- [ ] On Samsung A15: panoramic wallpaper loads + scrolls + survives apply/swap with identical behavior to current main.
- [ ] Logcat shows same "deferring decode" / "skipping decode" / "already current" guards working (regression-free vs #4/#4b/#4c/#7).
- [ ] Short README at `docs/blueprints/panoramic_wallpaper.md` explaining how to use the renderer in any Android app.

## What is NOT in scope for Phase 1

- Refactoring video, frame scrub, canvas scenes, effect layers — those wait for later phases.
- Changing the SharedPreferences cross-process pattern (works, well-documented in `tech_sharedprefs_multi_process.md`).
- Touching the broadcast / killProcess flow (just landed in #7, leave alone).
- Performance tweaks beyond what already exists (#4 / #4b / #4c guards stay).

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| Subtle behavior break (e.g., panoramic doesn't scroll on Samsung) | Validate on device before each commit; revert if any regression |
| Memory leak from poorly extracted bitmap lifecycle | `release()` is required public method; orchestrator calls on `onDestroy` |
| Future capabilities can't compose with the extracted renderer | Public contract is minimal (load + offset + draw); composability is preserved |
| Refactor creates a new "abstraction tax" with no payoff | Keep PanoramicWallpaperRenderer concrete (not abstract base); 200 LOC of clarity is the payoff |
