# iOS White Theme — Architecture Design

**Date:** 2026-04-26
**Author:** Claude (Opus 4.7) + Eduardo (user)
**Status:** Approved by user, ready for writing-plans

---

## Goal

Add a third visual theme to Pixora — **"Apple Store Fresh"** (white iOS native, Geist font, system blue accents) — selectable by the user in Settings, alongside the existing Black & Gold (night) and Cream Day themes.

## Constraints

- **Live switch** — no app restart needed
- **Persisted** across app launches (Hive)
- **Zero breaking changes** to existing widgets — they continue working with night/day, the new theme appears as a third option
- Eventually feeds into a subscription tier (subscribers get extra perks like ad removal + bonus PDF reader — out of scope for this design but kept in mind for the ThemeService API)

## Architecture Decisions

### D1. Token system → extend existing `HudTheme`

Pixora already uses Flutter's `ThemeExtension<HudTheme>` with `night` and `day` presets. Widgets read `context.hud.bg`, `context.hud.accent`, etc.

**Decision:** Add a third preset `HudTheme.iosWhite` to the same class. Zero refactor to widgets that already use `context.hud.*`.

**Rejected alternative:** A parallel `ThemeService` would duplicate infrastructure and create two sources of truth.

### D2. Typography → tokenize via three new fields on HudTheme

Currently widgets hardcode `fontFamily: 'Fraunces'` and `fontFamily: 'JetBrainsMono'`.

**Decision:** Add three nullable string fields to `HudTheme`:
- `displayFont` — for hero/headline text (Fraunces in night/day, Geist in iosWhite)
- `bodyFont` — for body text (Fraunces in night/day, Geist in iosWhite)
- `monoFont` — for technical labels (JetBrainsMono in night/day, GeistMono in iosWhite)

**Migration:** Replace hardcoded `fontFamily: 'Fraunces'` → `fontFamily: h.displayFont` widget by widget.

**Phase 1 fallback:** Widgets not yet migrated continue rendering Fraunces even when iosWhite is active. Visually mixed but does not break.

### D3. Reactivity → singleton `ThemeService` (ChangeNotifier)

Matches CLAUDE.md pattern ("Singleton, not Riverpod for services"). Holds `currentTheme: HudTheme` and `currentThemeId: String` ('night' | 'day' | 'iosWhite').

API:
- `ThemeService.instance.currentTheme: HudTheme`
- `ThemeService.instance.currentThemeId: String`
- `ThemeService.instance.setTheme(String id)` — persists + notifies
- `ThemeService.instance.init()` — reads from Hive on app start

Wired at `main.dart` root via `ListenableBuilder` wrapping `MaterialApp`. Theme change → MaterialApp rebuild → all `context.hud.*` reads update instantly.

### D4. Roll-out → big bang core, no feature flag

Because every widget already uses `context.hud.*`, adding a new HudTheme preset propagates everywhere automatically. No feature flag needed. Typography fallback (D2) means zero crashes during migration.

### D5. Status bar styling → `AnnotatedRegion<SystemUiOverlayStyle>` in HomePage

- Black & Gold (night): `Brightness.light` for status bar icons (white)
- Cream Day: `Brightness.dark` (black icons)
- iOS White: `Brightness.dark` (black icons)

Single AnnotatedRegion wrapping HomePage's Scaffold reads `h.isDark` to decide. ~5 lines.

### D6. Premium iOS touches (shadows, blur, micro-animations) → defer to Phase 2

Phase 1 ships colors + typography only. Visual polish (soft shadows, glassmorphism, transitions) is meaningful but adds widget-specific code. Better done in Phase 2 alongside per-section refactor.

### D7. "Auto" mode following OS → NOT in Phase 1

Three explicit options in Settings: `Black & Gold` / `Cream Day` / `iOS White`. Auto-mode (listen to MediaQuery.platformBrightness) is a Phase 3 nice-to-have.

---

## Phase 1 Scope (this session)

| # | Task | Files |
|---|---|---|
| 1 | Add `displayFont`/`bodyFont`/`monoFont` to `HudTheme` + presets for night/day | `lib/core/design/hud_tokens.dart` |
| 2 | Define `HudTheme.iosWhite` constant (palette + typography) | same file |
| 3 | Create `ThemeService` singleton (Hive-persisted) | `lib/core/services/theme_service.dart` (new) |
| 4 | Wrap MaterialApp with `ListenableBuilder` listening to ThemeService | `lib/main.dart` |
| 5 | Settings page → 3-radio theme picker | `lib/features/settings/presentation/settings_page.dart` |
| 6 | `AnnotatedRegion<SystemUiOverlayStyle>` in HomePage | `lib/features/home/presentation/home_page.dart` |
| 7 | Build + install + test live switch on device | n/a |

**Out of scope (Phase 2 — next session):**
- Per-widget refactor to migrate hardcoded fonts to `h.displayFont`
- Premium iOS visual touches (shadows, blur)
- Auto mode (follow OS)

## Success Criteria

- User can open Settings → "Tema visual" → tap "iOS White" → app's bg/accent/divider colors change instantly across all visible widgets
- Status bar icons flip from white to black correctly
- Choice persists across app restart
- Existing Black & Gold and Cream Day modes still work identically
- No widget crashes; widgets with hardcoded Fraunces continue rendering Fraunces even in iOS mode

## iOS White Palette (from Apple Store Fresh mockup #3)

| Token | Color | Usage |
|---|---|---|
| `bg` | `#FFFFFF` | Main background |
| `surface` | `#F2F2F7` | Cards, search bars |
| `surfaceHi` | `#E5E5EA` | Elevated surfaces |
| `text` | `#1C1C1E` | Primary text |
| `textDim` | `#8E8E93` | Secondary / labels |
| `divider` | `#3C3C43` @ 12% | Hairline borders |
| `accent` | `#007AFF` | iOS system blue (primary) |
| `accent2` | `#34C759` | iOS system green (success) |
| `displayFont` | `Geist` | Headlines |
| `bodyFont` | `Geist` | Body |
| `monoFont` | `GeistMono` | Mono / labels |
| `isDark` | `false` | Drives status bar |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Geist font not installed in pubspec | Add to `pubspec.yaml` assets/fonts during Phase 1 |
| Some widgets still hardcode Color(0x...) instead of `h.*` | Mixed visual during Phase 1 is acceptable; track and fix in Phase 2 |
| ThemeService init timing — first frame paint with default before Hive read | `await ThemeService.instance.init()` in main() before runApp |
| Hive box already used for credits/favorites — adding 'theme' key fits cleanly | Use a small dedicated box `pixora_theme` (single key) to avoid collisions |
