# iOS White Theme Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third selectable theme ("iOS White / Apple Store Fresh") to Pixora alongside the existing Black & Gold (night) and Cream Day modes, with live switching from Settings and persisted choice.

**Architecture:** Extend the existing `HudTheme` (Flutter `ThemeExtension`) with a third preset `iosWhite`. Add typography tokens (`displayFontFamily`, `bodyFontFamily`, `monoFontFamily`) so future widgets can read `h.displayFontFamily` instead of hardcoding 'Fraunces'. Singleton `ThemeService` (ChangeNotifier, Hive-persisted) wraps `MaterialApp` via `ListenableBuilder` so theme switches propagate without restart.

**Tech Stack:** Flutter, Riverpod (UI), Singleton ChangeNotifier (services per CLAUDE.md), Hive (persistence), google_fonts package (already in pubspec for Geist), AnnotatedRegion (status bar styling).

**No automated tests in Pixora.** Validation is manual on Samsung RF8X903KZ3K per CLAUDE.md.

**Source spec:** `docs/superpowers/specs/2026-04-26-ios-theme-architecture-design.md`

**Estimated total time:** ~2.5 hours implementation + 30 min device verification = 3 hours. Buffer for issues: 1 hour. Total: 4 hours.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/core/design/hud_tokens.dart` | MODIFY — add font family fields to HudTheme + iosWhite preset |
| `lib/core/services/theme_service.dart` | NEW — singleton ChangeNotifier + Hive persistence |
| `lib/main.dart` | MODIFY — init ThemeService, wrap MaterialApp with ListenableBuilder, dynamically apply HudTheme to ThemeData.extensions |
| `lib/features/settings/presentation/settings_page.dart` | MODIFY — add "Tema visual" section with 3 radio options |
| `lib/features/home/presentation/home_page.dart` | MODIFY — wrap Scaffold in AnnotatedRegion for status bar icon brightness |

---

## Task 1: Add font family tokens + iosWhite preset to HudTheme

**Files:**
- Modify: `lib/core/design/hud_tokens.dart`

- [ ] **Step 1.1: Read current hud_tokens.dart to confirm baseline (lines 146-220)**

Run: `Read D:/Orbix/Pixora-IA/lib/core/design/hud_tokens.dart`

Expected: see `class HudTheme extends ThemeExtension<HudTheme>` with `night` and `day` const presets and `copyWith()`.

- [ ] **Step 1.2: Add iOS White color constants near the existing nightBg/dayBg constants**

Add these inside `class HudTokens` near the other color constants (after the `dayDivider` line):

```dart
  // ── iOS White palette (Apple Store Fresh — picked from mockup #3) ──
  static const Color iosBg = Color(0xFFFFFFFF);          // pure white
  static const Color iosSurface = Color(0xFFF2F2F7);     // light gray cards
  static const Color iosSurfaceHi = Color(0xFFE5E5EA);   // elevated surface
  static const Color iosText = Color(0xFF1C1C1E);        // near-black
  static const Color iosTextDim = Color(0xFF8E8E93);     // system gray
  static const Color iosDivider = Color(0x1F3C3C43);     // hairline border 12%
  static const Color iosAccent = Color(0xFF007AFF);      // iOS system blue
  static const Color iosAccent2 = Color(0xFF34C759);     // iOS system green
```

- [ ] **Step 1.3: Add font family fields + presets to HudTheme**

In the `HudTheme` class (around line 147), add three new String fields and update the constructor + presets + copyWith.

Replace the existing `class HudTheme extends ThemeExtension<HudTheme>` definition (the data class part, NOT the night/day const yet):

```dart
class HudTheme extends ThemeExtension<HudTheme> {
  const HudTheme({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.text,
    required this.textDim,
    required this.divider,
    required this.accent,
    required this.accent2,
    required this.isDark,
    required this.displayFontFamily,
    required this.bodyFontFamily,
    required this.monoFontFamily,
  });

  final Color bg;
  final Color surface;
  final Color surfaceHi;
  final Color text;
  final Color textDim;
  final Color divider;
  final Color accent;
  final Color accent2;
  final bool isDark;

  /// Font family names. For widgets that need to render with the active theme's
  /// typography. Existing widgets that hardcode 'Fraunces' continue to work
  /// (mixed visual during Phase 1 is acceptable; Phase 2 migrates per-widget).
  final String displayFontFamily;
  final String bodyFontFamily;
  final String monoFontFamily;

  /// Convenience gold aliases (same as accent/accent2 but clearer intent).
  Color get gold => accent;
  Color get goldBright => accent2;
```

- [ ] **Step 1.4: Update night preset to include the new font fields**

Replace the existing `static const HudTheme night = HudTheme(...)` block:

```dart
  static const HudTheme night = HudTheme(
    bg: HudTokens.nightBg,
    surface: HudTokens.nightSurface,
    surfaceHi: HudTokens.nightSurfaceHi,
    text: HudTokens.nightText,
    textDim: HudTokens.nightTextDim,
    divider: HudTokens.nightDivider,
    accent: HudTokens.gold,
    accent2: HudTokens.goldBright,
    isDark: true,
    displayFontFamily: 'Fraunces',
    bodyFontFamily: 'Fraunces',
    monoFontFamily: 'JetBrainsMono',
  );
```

- [ ] **Step 1.5: Update day preset to include the new font fields**

Replace the existing `static const HudTheme day = HudTheme(...)` block:

```dart
  static const HudTheme day = HudTheme(
    bg: HudTokens.dayBg,
    surface: HudTokens.daySurface,
    surfaceHi: HudTokens.daySurfaceHi,
    text: HudTokens.dayText,
    textDim: HudTokens.dayTextDim,
    divider: HudTokens.dayDivider,
    accent: HudTokens.goldDay,
    accent2: HudTokens.goldDeep,
    isDark: false,
    displayFontFamily: 'Fraunces',
    bodyFontFamily: 'Fraunces',
    monoFontFamily: 'JetBrainsMono',
  );
```

- [ ] **Step 1.6: Add iosWhite preset right after `day`**

Add this NEW const directly after the `day` block:

```dart
  /// iOS White ("Apple Store Fresh") — picked by user 2026-04-26.
  /// Phase 1 ships colors + font tokens. Per-widget font migration = Phase 2.
  static const HudTheme iosWhite = HudTheme(
    bg: HudTokens.iosBg,
    surface: HudTokens.iosSurface,
    surfaceHi: HudTokens.iosSurfaceHi,
    text: HudTokens.iosText,
    textDim: HudTokens.iosTextDim,
    divider: HudTokens.iosDivider,
    accent: HudTokens.iosAccent,
    accent2: HudTokens.iosAccent2,
    isDark: false,
    displayFontFamily: 'Geist',
    bodyFontFamily: 'Geist',
    monoFontFamily: 'GeistMono',
  );
```

- [ ] **Step 1.7: Update copyWith to include new fields**

Replace the existing `copyWith` method:

```dart
  @override
  HudTheme copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHi,
    Color? text,
    Color? textDim,
    Color? divider,
    Color? accent,
    Color? accent2,
    bool? isDark,
    String? displayFontFamily,
    String? bodyFontFamily,
    String? monoFontFamily,
  }) =>
      HudTheme(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceHi: surfaceHi ?? this.surfaceHi,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        divider: divider ?? this.divider,
        accent: accent ?? this.accent,
        accent2: accent2 ?? this.accent2,
        isDark: isDark ?? this.isDark,
        displayFontFamily: displayFontFamily ?? this.displayFontFamily,
        bodyFontFamily: bodyFontFamily ?? this.bodyFontFamily,
        monoFontFamily: monoFontFamily ?? this.monoFontFamily,
      );
```

- [ ] **Step 1.8: Update lerp method (if exists) to include new fields**

Find the existing `lerp` method. For non-color fields, lerp is just "use t < 0.5 ? a : b". Update like:

```dart
        displayFontFamily: t < 0.5 ? displayFontFamily : (other?.displayFontFamily ?? displayFontFamily),
        bodyFontFamily: t < 0.5 ? bodyFontFamily : (other?.bodyFontFamily ?? bodyFontFamily),
        monoFontFamily: t < 0.5 ? monoFontFamily : (other?.monoFontFamily ?? monoFontFamily),
```

If `lerp` doesn't exist, skip this step (Flutter generates a no-op default).

- [ ] **Step 1.9: Verify analyze passes**

Run: `flutter analyze lib/core/design/hud_tokens.dart`

Expected: `No issues found!` or only info-level warnings.

- [ ] **Step 1.10: Commit Task 1**

```bash
git add lib/core/design/hud_tokens.dart
git commit -m "feat(theme): extend HudTheme with iOS White preset + font family tokens

- Add iosWhite color constants (#FFFFFF bg, #007AFF accent, #1C1C1E text)
- Add displayFontFamily/bodyFontFamily/monoFontFamily String tokens to HudTheme
- night/day presets keep Fraunces + JetBrainsMono
- iosWhite preset uses Geist + GeistMono
- Update copyWith + lerp accordingly

Phase 1 of iOS theme implementation (see docs/superpowers/specs/...)
"
```

---

## Task 2: Create ThemeService singleton with Hive persistence

**Files:**
- Create: `lib/core/services/theme_service.dart`

- [ ] **Step 2.1: Verify Hive is already initialized somewhere**

Run: `grep -rn "Hive.initFlutter\|Hive.openBox" D:/Orbix/Pixora-IA/lib/main.dart`

Expected: Hive is set up in main.dart. Note the box names already used (e.g. 'pixora_credits', 'favorites').

- [ ] **Step 2.2: Write the ThemeService**

Create `lib/core/services/theme_service.dart` with this exact content:

```dart
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../design/hud_tokens.dart';

/// Manages the active Pixora visual theme.
///
/// Three presets supported (per docs/superpowers/specs/2026-04-26-ios-theme-architecture-design.md):
///   - 'night'    → HudTheme.night    (Black & Gold — default)
///   - 'day'      → HudTheme.day      (cream day mode)
///   - 'iosWhite' → HudTheme.iosWhite (Apple Store Fresh)
///
/// Singleton ChangeNotifier per CLAUDE.md pattern. UI listens via ListenableBuilder
/// at the MaterialApp root; switching propagates everywhere reading context.hud.*.
///
/// Persistence: a tiny Hive box 'pixora_theme' stores the active id. The default
/// when nothing is set is 'night'.
class ThemeService extends ChangeNotifier {
  ThemeService._();
  static final instance = ThemeService._();

  static const _boxName = 'pixora_theme';
  static const _key = 'active';
  static const _defaultId = 'night';

  String _activeId = _defaultId;
  Box<String>? _box;

  /// The active theme id ('night' | 'day' | 'iosWhite').
  String get activeId => _activeId;

  /// The corresponding HudTheme instance for the active id.
  HudTheme get currentTheme {
    switch (_activeId) {
      case 'iosWhite':
        return HudTheme.iosWhite;
      case 'day':
        return HudTheme.day;
      case 'night':
      default:
        return HudTheme.night;
    }
  }

  /// Open the Hive box and read the persisted choice. Call once from main()
  /// before runApp so the first frame paints with the right theme.
  Future<void> init() async {
    try {
      _box = await Hive.openBox<String>(_boxName);
      final stored = _box?.get(_key);
      if (stored != null && _isValidId(stored)) {
        _activeId = stored;
      }
    } catch (e) {
      debugPrint('[ThemeService] init failed (using default night): $e');
    }
  }

  /// Switch to a new theme. Persists immediately and notifies listeners so the
  /// UI rebuilds with the new HudTheme. Pass one of: 'night', 'day', 'iosWhite'.
  Future<void> setTheme(String id) async {
    if (!_isValidId(id)) {
      debugPrint('[ThemeService] ignoring unknown theme id "$id"');
      return;
    }
    if (_activeId == id) return;
    _activeId = id;
    try {
      await _box?.put(_key, id);
    } catch (e) {
      debugPrint('[ThemeService] persist failed: $e');
    }
    notifyListeners();
  }

  bool _isValidId(String id) =>
      id == 'night' || id == 'day' || id == 'iosWhite';

  /// Human-readable label for the active id (used in Settings).
  static String labelFor(String id) {
    switch (id) {
      case 'iosWhite':
        return 'iOS White';
      case 'day':
        return 'Cream Day';
      case 'night':
      default:
        return 'Black & Gold';
    }
  }

  /// Short tagline shown under each option in Settings.
  static String taglineFor(String id) {
    switch (id) {
      case 'iosWhite':
        return 'Apple Store · blanco · system blue';
      case 'day':
        return 'Cremoso · día · gold suave';
      case 'night':
      default:
        return 'Default · negro profundo · gold';
    }
  }

  /// All theme ids in display order (Settings UI uses this).
  static const List<String> allIds = ['night', 'day', 'iosWhite'];
}
```

- [ ] **Step 2.3: Verify analyze passes for the new file**

Run: `flutter analyze lib/core/services/theme_service.dart`

Expected: `No issues found!`

- [ ] **Step 2.4: Commit Task 2**

```bash
git add lib/core/services/theme_service.dart
git commit -m "feat(theme): add ThemeService singleton with Hive persistence

ChangeNotifier-based service holding the active theme id.
Reads from/writes to a tiny Hive box 'pixora_theme'.
API: instance.activeId, instance.currentTheme, instance.setTheme(id), init().
Static helpers labelFor/taglineFor/allIds for Settings UI.
"
```

---

## Task 3: Wire ThemeService into main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 3.1: Read current main.dart structure**

Run: `Read D:/Orbix/Pixora-IA/lib/main.dart`

Find: the `void main() async` function and the MaterialApp instantiation.

- [ ] **Step 3.2: Import ThemeService at the top of main.dart**

Add to the imports section:

```dart
import 'core/services/theme_service.dart';
```

- [ ] **Step 3.3: Initialize ThemeService in main() before runApp**

Find the line `await Hive.initFlutter();` (or similar Hive init). After it, add:

```dart
  await ThemeService.instance.init();
```

If there's no explicit Hive.initFlutter line and Hive is initialized elsewhere, add `await ThemeService.instance.init();` after all the existing async setup but BEFORE `runApp(...)`.

- [ ] **Step 3.4: Wrap MaterialApp with ListenableBuilder**

Find the MaterialApp instantiation. It currently has something like:

```dart
return MaterialApp(
  theme: ThemeData(extensions: [HudTheme.night, ...]),
  home: const HomePage(),
  ...
);
```

Replace with:

```dart
return ListenableBuilder(
  listenable: ThemeService.instance,
  builder: (context, _) {
    final hud = ThemeService.instance.currentTheme;
    return MaterialApp(
      theme: ThemeData(
        // Preserve existing ThemeData properties — only mutate the extensions.
        // Other fields (typography, brightness, scaffoldBackgroundColor, etc.)
        // stay as before. The HudTheme extension is what context.hud reads.
        useMaterial3: true,
        scaffoldBackgroundColor: hud.bg,
        extensions: [hud],
      ),
      home: const HomePage(),
      // ... preserve all other existing MaterialApp props (debugShowCheckedModeBanner, etc.)
    );
  },
);
```

**IMPORTANT:** Read your current MaterialApp invocation FIRST before this edit, and preserve all existing properties (locales, navigatorKey, debugShowCheckedModeBanner, etc.). Only the wrapping with ListenableBuilder + dynamic extensions is new.

- [ ] **Step 3.5: Verify analyze passes**

Run: `flutter analyze lib/main.dart`

Expected: `No issues found!` (info-level warnings OK)

- [ ] **Step 3.6: Commit Task 3**

```bash
git add lib/main.dart
git commit -m "feat(theme): wire ThemeService into MaterialApp via ListenableBuilder

main() now awaits ThemeService.instance.init() before runApp so the first
frame paints with the persisted theme. MaterialApp is wrapped in a
ListenableBuilder that rebuilds when the user switches theme — propagates
to all widgets reading context.hud.*.
"
```

---

## Task 4: Add theme picker section in Settings

**Files:**
- Modify: `lib/features/settings/presentation/settings_page.dart`

- [ ] **Step 4.1: Read settings_page.dart to understand existing pattern**

Run: `Grep -n "class SettingsPage\|build\|HudPrimaryButton\|HudSectionHeader" D:/Orbix/Pixora-IA/lib/features/settings/presentation/settings_page.dart`

Identify: where existing setting sections are defined, what widget pattern they use (most likely `HudSectionHeader` followed by a `Card` or list of tiles).

- [ ] **Step 4.2: Add ThemeService import at the top**

```dart
import '../../../core/services/theme_service.dart';
```

(Verify the import path is correct — depends on settings_page.dart depth.)

- [ ] **Step 4.3: Add a private `_ThemePickerSection` widget at the bottom of the file**

Add this widget definition outside the SettingsPage class (typically at the file bottom):

```dart
class _ThemePickerSection extends StatelessWidget {
  const _ThemePickerSection();

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final activeId = ThemeService.instance.activeId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text(
                'TEMA VISUAL',
                style: TextStyle(
                  fontFamily: h.monoFontFamily,
                  fontSize: 11,
                  letterSpacing: 2.4,
                  color: h.textDim,
                ),
              ),
            ),
            for (final id in ThemeService.allIds)
              _ThemeOption(
                id: id,
                active: id == activeId,
                onTap: () => ThemeService.instance.setTheme(id),
              ),
          ],
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.id,
    required this.active,
    required this.onTap,
  });
  final String id;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: h.divider, width: 0.5),
          ),
          color: active ? h.surfaceHi.withValues(alpha: 0.5) : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? h.accent : h.divider,
                  width: 1.5,
                ),
                color: active ? h.accent : Colors.transparent,
              ),
              child: active
                  ? Icon(Icons.check, size: 14, color: h.bg)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ThemeService.labelFor(id),
                    style: TextStyle(
                      fontFamily: h.bodyFontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: h.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ThemeService.taglineFor(id),
                    style: TextStyle(
                      fontFamily: h.monoFontFamily,
                      fontSize: 10,
                      letterSpacing: 0.6,
                      color: h.textDim,
                    ),
                  ),
                ],
              ),
            ),
            // Color swatch preview: shows the theme's bg + accent
            _SwatchPreview(themeId: id),
          ],
        ),
      ),
    );
  }
}

class _SwatchPreview extends StatelessWidget {
  const _SwatchPreview({required this.themeId});
  final String themeId;

  @override
  Widget build(BuildContext context) {
    HudTheme preview;
    switch (themeId) {
      case 'iosWhite':
        preview = HudTheme.iosWhite;
        break;
      case 'day':
        preview = HudTheme.day;
        break;
      default:
        preview = HudTheme.night;
    }
    return Container(
      width: 44,
      height: 28,
      decoration: BoxDecoration(
        color: preview.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: preview.divider, width: 1),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 6,
            top: 6,
            bottom: 6,
            child: Container(
              width: 10,
              decoration: BoxDecoration(
                color: preview.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4.4: Insert `_ThemePickerSection()` into the SettingsPage build()**

Find the SettingsPage `build()` method's `Column` or `ListView` of children. Add `const _ThemePickerSection()` near the top (after any header/profile section, before the destructive sign-out at the bottom).

For example, if Settings has:

```dart
ListView(
  children: [
    _ProfileHeader(),
    _AdsToggle(),
    _LanguageSection(),
    // ...
    _SignOutButton(),
  ],
)
```

Insert:

```dart
ListView(
  children: [
    _ProfileHeader(),
    const _ThemePickerSection(),  // ← NEW
    _AdsToggle(),
    _LanguageSection(),
    // ...
    _SignOutButton(),
  ],
)
```

If you can't find a clean insertion point, add it near the top of the body.

- [ ] **Step 4.5: Verify analyze passes**

Run: `flutter analyze lib/features/settings/presentation/settings_page.dart`

Expected: `No issues found!` (info-level OK)

- [ ] **Step 4.6: Commit Task 4**

```bash
git add lib/features/settings/presentation/settings_page.dart
git commit -m "feat(settings): add Tema visual section with 3-option theme picker

ListenableBuilder wraps the picker so it reflects the active theme
automatically. Each option shows label + tagline + a small color swatch
preview (bg + accent). Tap → ThemeService.setTheme().
"
```

---

## Task 5: Add AnnotatedRegion for status bar styling in HomePage

**Files:**
- Modify: `lib/features/home/presentation/home_page.dart`

- [ ] **Step 5.1: Add SystemUiOverlayStyle import at top of home_page.dart**

```dart
import 'package:flutter/services.dart';
```

- [ ] **Step 5.2: Wrap the Scaffold in AnnotatedRegion**

Find the `build()` method's return Scaffold(...). Replace:

```dart
return Scaffold(
  backgroundColor: h.bg,
  extendBodyBehindAppBar: _isWallpapersTab,
  appBar: _buildAppBar(),
  body: IndexedStack(index: _currentIndex, children: _pages),
  bottomNavigationBar: _buildBottomNav(),
);
```

With:

```dart
return AnnotatedRegion<SystemUiOverlayStyle>(
  value: h.isDark
      ? SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: h.bg,
          systemNavigationBarIconBrightness: Brightness.light,
        )
      : SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: h.bg,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
  child: Scaffold(
    backgroundColor: h.bg,
    extendBodyBehindAppBar: _isWallpapersTab,
    appBar: _buildAppBar(),
    body: IndexedStack(index: _currentIndex, children: _pages),
    bottomNavigationBar: _buildBottomNav(),
  ),
);
```

- [ ] **Step 5.3: Verify analyze passes**

Run: `flutter analyze lib/features/home/presentation/home_page.dart`

Expected: `No issues found!`

- [ ] **Step 5.4: Commit Task 5**

```bash
git add lib/features/home/presentation/home_page.dart
git commit -m "feat(theme): swap status bar icon brightness based on active theme

AnnotatedRegion wraps HomePage Scaffold. h.isDark drives whether status
bar icons are light (Black & Gold) or dark (Cream Day, iOS White).
Also tints the Android navigation bar to match the theme bg.
"
```

---

## Task 6: Build, install, and verify on device

**Files:** none (verification step)

- [ ] **Step 6.1: Build debug APK**

Run: `flutter build apk --debug 2>&1 | tail -10`

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

If build fails: read the error output, fix the offending file, and re-run. Common issues: missing import, typo in class name, leftover hardcoded reference.

- [ ] **Step 6.2: Install on Samsung device**

Run: `adb -s RF8X903KZ3K install -r build/app/outputs/flutter-apk/app-debug.apk 2>&1 | tail -3`

Expected: `Success`.

If `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: per CLAUDE.md run `adb -s RF8X903KZ3K uninstall com.orbix.pixora && adb -s RF8X903KZ3K install build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 6.3: Force-stop app and clear logcat**

Run:
```bash
adb -s RF8X903KZ3K shell am force-stop com.orbix.pixora
adb -s RF8X903KZ3K logcat -c
```

- [ ] **Step 6.4: Launch app and verify default theme is Black & Gold**

Run: `adb -s RF8X903KZ3K shell am start -n com.orbix.pixora/.MainActivity`

Manually verify on device:
- App opens with Black & Gold theme (existing default)
- Status bar icons are WHITE (visible against black)

- [ ] **Step 6.5: Manually navigate to Settings → Tema visual**

User taps SET tab in bottom nav, scrolls to find "TEMA VISUAL" section. Three options visible: Black & Gold (selected), Cream Day, iOS White.

- [ ] **Step 6.6: Tap "iOS White" — verify live switch**

Expected on device:
- App background flips to white
- Accent color changes from gold to iOS blue
- Status bar icons flip from white to BLACK (now visible on white bg)
- Existing widgets that hardcode 'Fraunces' may still render in Fraunces — that's expected for Phase 1 (Phase 2 migrates them)

If white doesn't appear: check `flutter analyze main.dart` — the ListenableBuilder wrapping may have lost the dynamic `extensions:` part.

- [ ] **Step 6.7: Tap "Cream Day" — verify second switch works**

Expected: cream/day-mode bg, gold accent, dark status bar icons.

- [ ] **Step 6.8: Force-stop and reopen — verify persistence**

Run:
```bash
adb -s RF8X903KZ3K shell am force-stop com.orbix.pixora
adb -s RF8X903KZ3K shell am start -n com.orbix.pixora/.MainActivity
```

Expected: app reopens with the LAST chosen theme (e.g. iOS White if that's what we left it on).

- [ ] **Step 6.9: Switch back to Black & Gold (default state for next session)**

User taps Settings → Tema visual → Black & Gold.

- [ ] **Step 6.10: Read logcat for any theme-related crashes**

Run: `adb -s RF8X903KZ3K logcat -d -t 1000 2>/dev/null | grep -iE "ThemeService|HudTheme|FATAL|AndroidRuntime" | tail -20`

Expected: at most info-level "[ThemeService] init" lines, no FATAL.

- [ ] **Step 6.11: Commit Phase 1 completion marker**

```bash
git commit --allow-empty -m "feat(theme): Phase 1 complete — iOS White theme switching live on device

Verified on Samsung RF8X903KZ3K:
- Default boot uses persisted theme
- Live switch between Black & Gold / Cream Day / iOS White
- Status bar icons flip correctly per theme.isDark
- No crashes; widgets hardcoding Fraunces remain in Fraunces (Phase 2 task)

Phase 2 = per-widget refactor + premium iOS visual touches (shadows/blur).
"
```

---

## Self-Review Notes

**Spec coverage check:**
- ✅ D1 (extend HudTheme) → Task 1
- ✅ D2 (typography tokens) → Task 1 steps 1.3-1.6
- ✅ D3 (singleton ThemeService) → Task 2
- ✅ D4 (no feature flag) → addressed via auto-fallback in Task 1 design
- ✅ D5 (AnnotatedRegion status bar) → Task 5
- ✅ D6 (defer premium touches) → out-of-scope by design
- ✅ D7 (no auto mode) → out-of-scope by design
- ✅ Hive box `pixora_theme` → Task 2 step 2.2

**Type consistency check:**
- HudTheme constructor params match across constructor + night + day + iosWhite + copyWith
- `displayFontFamily`/`bodyFontFamily`/`monoFontFamily` consistent everywhere
- `ThemeService.allIds` matches the switch in `currentTheme` getter (`night`, `day`, `iosWhite`)

**Placeholder scan:** no TBD/TODO/empty steps. All code blocks contain actual implementations.

**Scope check:** Phase 1 only — focused. Per-widget font migration explicitly deferred to Phase 2 with note.
