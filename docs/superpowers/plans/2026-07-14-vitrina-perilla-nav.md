# Plan: "Vitrina + Perilla" Navigation Redesign

> Handoff doc so this work can continue on any machine. Everything design-related
> already lives on branch `play-store-estable-mdecbm`. This file carries the plan
> + decisions so a fresh Claude Code session (e.g. on the laptop) can resume with
> full context. Written 2026-07-14.

## What we're building

Replace the current bottom navigation (a `BottomNavigationBar` with 14 tabs, driven
by 3 hand-synced parallel lists in `home_page.dart`) with:

1. **"Vitrina" full-bleed home** — no bottom nav. The wallpaper fills the screen
   edge-to-edge (immersive). Floating glass-morphism UI on top: a top row
   (avatar + glass pills), a large serif-italic title block near the bottom
   (section name + kicker + Aplicar / Vista previa), and a draggable bottom sheet
   with a Trending row. Content breathes all the way to the bottom edge.
2. **"Perilla" (dial) navigation** — a small gold FAB on the LEFT edge, vertically
   centered. Tapping it opens a glass overlay (blurred scrim) with a curved radial
   dial. Drag up/down to rotate through sections; centered option is "active" and
   live-previews (bg tint + section label). Aplicar (or tapping the active option)
   commits + navigates; tapping the scrim cancels.

**Visual language**: "Elegante" — noir-gold, Fraunces italic serif. Already close
to what the app ships today (`_HoloRibbonAppBar` uses `GoogleFonts.fraunces` +
`HudTokens.foilPalette`). This redesign is mostly **structural**, not a new look.

**Working HTML prototypes** (reference for exact mechanics + geometry):
- `docs/design/home_fullbleed_variants.html` — chosen layout is **Variante 2 "Vitrina"**
- `docs/design/dial_elegante_glass.html` + `docs/design/_dial_engine.js` — the dial motor
- `docs/design/shots/home_2-vitrina.png` — rendered screenshot of the pick

## Decisions locked (2026-07-14, with Eduardo)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Stories / Ringtones / AI Create (don't fit the 10-item dial) | **"Más" tab** — an 11th dial item opening a small menu with the three |
| 2 | Ship as one release or two | **Two** — Release A = structural refactor (verifiable 1:1 vs today), Release B = dial + coach-marks |
| 3 | iOS reduced nav | **Android-only launch.** Do NOT build any iOS-specific nav. Keep the `iosVisible` bool in the section registry (honors existing `if (!Platform.isIOS)` convention so nothing breaks if compiled) but invest zero design effort in iOS pills/dial |
| 4 | Onboarding tour (breaks — points at old tabs) | **Simple animated hint on the FAB** ("arrastra para explorar"), retire the old step-by-step nav tour |
| — | Settings entry point | Gear icon in the floating top row (mirrors avatar-tap-to-Perfil pattern), `Navigator.push` — NOT a dial item |

## Current-state map (from architect exploration)

`lib/features/home/presentation/home_page.dart`:
- 3 parallel lists that must stay in sync (the foot-gun this redesign kills):
  `_pages` (L214-229), `_titles` (L236-251), bottom-nav `items` (`_NavItemData`, L567-602).
- Tab switching: plain `int _currentIndex` (L48) + `setState` (L609) → `IndexedStack(index: _currentIndex, children: _pages)` (L631). All pages stay mounted, so scroll + Riverpod state are preserved.
- `Scaffold`: `appBar: _buildAppBar()` (title from `_titles[_currentIndex]`), `body`, `bottomNavigationBar: _buildBottomNav()` (L628-634).
- Real 14-tab order (Android): 0 WALL, 1 LIVE, 2 3D, 3 AMOR, 4 CULT, 5 EVNT, 6 AURA, 7 ARC, 8 STOR, 9 DAY, 10 TON, 11 IA, 12 FAV, 13 SET. iOS keeps only WALL/FAV/SET.
- `_isWallpapersTab` (L231) gates the AppBar search icon to tab 0 only.
- `AuraPage` (`aura_page.dart:46`) and `AIGeneratePage` (`ai_generate_page.dart:773`) nest their OWN `Scaffold` inside the IndexedStack body. Every other section page is bare content relying on the outer AppBar title.
- `WallpapersPage` (`wallpapers_page.dart:64-98`) already has `HeroBanner` (52%-height holo-foil carousel, `hero_banner.dart`) + `PixoraDailyBanner` + `_TrendingRow` — reuse for the Vitrina featured + trending sheet.
- Reusable `GlassmorphPill` at `lib/core/widgets/glassmorph_pill.dart`. Full-screen `BackdropFilter` precedent at `lib/core/widgets/offline_modal.dart:133-134` (`ImageFilter.blur(16,16)`).

## Coupling that breaks / needs remap (lower risk than feared)

- **No deep-link / FCM tab routing exists.** `push_notification_service.dart` only handles `text_cms_invalidate` + `catalog_invalidate` (cache), never navigates by index. `main.dart:42-43` `pixoraNavigatorKey` is dead weight. No `onGenerateRoute`.
- **Hardcoded index** — `home_page.dart:107` Welcome Gift does `setState(() => _currentIndex = 2)` (assumes 2 == 3D). Remap to `HomeSection.tresD`.
- **Coach-mark tour** — `_navKeys` (16 GlobalKeys, L55-56) threaded into tabs (L855-869), `_buildSteps()` (L147-172) targets old nav order. Whole tour breaks → replaced by FAB hint (decision 4). The real trigger is a Hive flag in `training_service.dart` checked in initState (L183-192), NOT the stale GlobalKey doc-comment at L61 — so no GlobalKey plumbing to unwind, just retire the tour content.
- **Analytics continuity** — `AnalyticsService.instance.trackTabView(label.toLowerCase())` (L608) fires `tab_viewed` with `section` = wall/live/3d/amor/cult/evnt/aura/arc/stor/day/ton/ia/fav/set (`analytics_service.dart:156-157`). Feeds admin dashboard ENGAGEMENT tab. **PRESERVE these exact string values** in the new `HomeSection` registry's `analyticsKey`.
- `_isWallpapersTab` (L231) — trivial remap, don't forget.

## Architecture

- **Single source of truth**: `enum HomeSection` + `const List<HomeSectionMeta> kHomeSections`
  (label, kicker, icon, bgTintId, `analyticsKey`, `iosVisible`, `heroCapable`) in dial order.
  Collapses the 3 parallel lists into one file.
- **`VitrinaShell`** (new) = full-bleed `Stack`: bg layer (active/previewed tint or hero image)
  → section content (same widgets as `_pages` today, keyed by `HomeSection` via IndexedStack)
  → floating top row → hero title block (only `heroCapable` sections) → `PerillaFab` → `DialOverlay`.
- **Hero-capable** (Estáticos, Live, 3D, Amor, Cultura, Eventos, Día, Arcano) get the bottom
  title block w/ Aplicar / Vista previa. **Non-hero** (AURA, Favoritos) keep bare content BUT the
  shell reserves top padding (`topBarHeight + MediaQuery.padding.top`) instead of overlapping —
  else floating pills collide with list items (deviation from the HTML prototype, which only ever
  shows imagery behind the UI).
- **Section state**: keep `IndexedStack` for the 10 dial sections (zero regression). Settings /
  Stories / Ringtones / AI Create are `Navigator.push` routes (Stories/Ringtones/AI live under
  the "Más" menu), not IndexedStack members.
- **Riverpod, not singleton**: dial transient state (`rot`, `activeIdx`, `isDragging`, `isOpen`)
  → `StateNotifierProvider` in `lib/features/home/providers/dial_provider.dart`. It's UI-level
  state with no business logic — must NOT become a `.instance` singleton.

### Dial gesture — translate `_dial_engine.js`

Reference geometry (`_dial_engine.js:37,50-66`): `STEP=25°`, hub `CX=-70`, radius `R=250`,
`cy = screenHeight/2 + 8`, authored for a ~360px mock phone. Express `CX`/`R` as **fractions of
device width** (`CX ≈ -0.19*w`, `R ≈ 0.69*w`) so it scales; validate on Samsung + one smaller device.

Per-option per-frame:
```
ang     = i*STEP - rot           // degrees
theta   = ang * pi/180
x       = CX + R*cos(theta)
y       = cy + R*sin(theta)
d       = |ang|
scale   = max(0.5, 1 - d/150)
opacity = d>78 ? 0 : max(0, 1 - d/72)
active  = d < STEP/2
```
Drive with `AnimatedBuilder` on the dial state (`ValueNotifier<double>` rot), NOT `setState`
per frame; wrap arc in `RepaintBoundary` (app convention, e.g. home_page.dart:762-772).
- Drag: `onVerticalDragUpdate` → `rot += dy*0.42; rot.clamp(-STEP*0.5, (n-1)*STEP + STEP*0.5)`.
  Recompute `idx=(rot/STEP).round()`; on change, fire transient preview (bg tint + title).
- Drag end: snap via `AnimationController` `rot → idx*STEP` (~350-500ms, `Curves.easeOutCubic`).
- Tap option: `if (i==activeIdx && !moved) applyAndClose(); else snapTo(i)`. Track `moved` via
  cumulative drag vs `kTouchSlop` (not the JS 1px, that's mouse-tuned).
- **Fix, don't copy**: JS scrim-cancel leaves the last-dragged tint forever (`_dial_engine.js:106`).
  In Flutter, scrim-cancel must **revert** the transient preview to the committed `HomeSection`
  before closing. Apply/active-tap commits: set real `HomeSection`, fire
  `AnalyticsService.instance.trackTabView(section.analyticsKey)`, `HapticFeedback.selectionClick()`,
  animate closed.

### Glass-morphism

Scrim: `BackdropFilter(ImageFilter.blur(11,11))` in `ClipRect`/`Positioned.fill` +
`RadialGradient(center: Alignment(-1.3,0), radius:1.3, ...)`. Precedent: `offline_modal.dart:133-134`.
Floating pills: extend `glassmorph_pill.dart`, don't hand-roll.

## Build order

### Release A — structural refactor (this is what to build first)
1. `lib/features/home/presentation/models/home_section.dart` (new) — enum + `kHomeSections`
   registry. Zero behavior change. Ship, verify `flutter analyze` clean.
2. `widgets/vitrina_top_bar.dart` + `widgets/vitrina_shell.dart` (new, minimal) — strip
   `_HoloRibbonAppBar`/`_EmberReactiveNav`, replace with shell wired to a **temporary plain
   selector** (no dial yet) to prove content pages render full-bleed, incl. AuraPage/AIGeneratePage
   nested Scaffolds (watch for double-background/double-SafeArea seams).
3. Modify `home_page.dart`: swap in `VitrinaShell`, remap `_currentIndex=2` (L107) → `HomeSection.tresD`,
   remap `_isWallpapersTab` (L231), delete `_buildBottomNav`/`_EmberReactiveNav`/`_buildAppBar`/
   `_HoloRibbonAppBar` + support classes once verified equivalent.
4. Preserve all credit / protect-prompt / welcome-gift logic (L47-357), just re-point at `HomeSection`.
5. `flutter analyze lib/features/home` + device smoke test. This release should be verifiable 1:1
   against today's behavior (same sections reachable, same analytics keys, same apply flows).

### Release B — dial + polish
6. `providers/dial_provider.dart` (new) — pure gesture/geometry, unit-test against JS numbers.
7. `widgets/dial/perilla_fab.dart`, `dial_overlay.dart`, `dial_option.dart` (new) — wire to provider.
8. `widgets/vitrina_hero_title.dart` (new) — Aplicar/Vista previa call into EXISTING apply flow
   (`wallpaper_preview_page.dart:342` `AdService.instance.showInterstitialAd(...)`) — do NOT
   reimplement ads/credits/stats.
9. "Más" menu page for Stories/Ringtones/AI Create (decision 1).
10. Retire coach-mark nav tour, add animated FAB hint (decision 4). `training_service.dart` Hive
    flag mechanism is nav-agnostic — only the tour content changes.

## Smoke test on Samsung (RF8X903KZ3K)

1. All 10 dial sections open; previously-active section's provider/scroll state survives a round
   trip through the dial (IndexedStack preservation).
2. Apply/install on a hero section still routes through `AdService.instance.showInterstitialAd` +
   `CreditService` + `WallpaperStatsService` exactly as before.
3. AURA nested Scaffold renders with no seam.
4. Scrim-cancel does NOT leave a stale preview tint/title.
5. FAB hint shows on fresh install; retired tour doesn't crash (Hive flag reset via Settings).
6. `tab_viewed` analytics still carry the same `section` string values as pre-redesign.
7. Full-screen scrim blur perf-tested on LIVE + 3D tabs (heavier GPU), not just Wallpapers.

## Constraints (CLAUDE.md — must honor)

- MainActivity extends `AudioServiceActivity` (not FlutterActivity).
- Don't reimplement `AdService` / `CreditService` / `WallpaperStatsService` — every apply/download
  goes through `AdService.instance.showInterstitialAd`.
- Catalog fetching uses existing patterns; bilingual strings via `LocaleHelper`.
- No automated tests — validation is manual on device.
