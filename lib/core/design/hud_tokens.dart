import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Black & Gold design tokens.
///
/// Primary design direction chosen 2026-04-19 (master doc §21).
/// Palette: negro tinta + oro. Typography: Playfair Display (display),
/// Cormorant Garamond (serif italic), Inter (UI/labels/mono).
///
/// Class name kept as `HudTokens` for backward compatibility with all the
/// import sites during the migration.
class HudTokens {
  HudTokens._();

  // ── Palette ───────────────────────────────────────────────────────────
  // Night mode (primary — Pixora is mostly dark).
  static const Color nightBg = Color(0xFF000000); // ink
  static const Color nightSurface = Color(0xFF0A0604); // ink-2 warm near-black
  static const Color nightSurfaceHi = Color(0xFF151008); // ink-3
  static const Color nightText = Color(0xFFF0E8D6); // cream
  static const Color nightTextDim = Color(0xFF8A7A56); // gold-dim
  static const Color nightDivider = Color(0x33C9A650); // gold @ 20%

  // Day mode.
  static const Color dayBg = Color(0xFFF4ECD8); // warm cream page
  static const Color daySurface = Color(0xFFECE2C8);
  static const Color daySurfaceHi = Color(0xFFE0D4B4);
  static const Color dayText = Color(0xFF1A1208);
  static const Color dayTextDim = Color(0xFF5A4E36);
  static const Color dayDivider = Color(0x33865F20);

  // ── iOS White palette (Apple Store Fresh — picked from mockup #3) ──
  static const Color iosBg = Color(0xFFFFFFFF); // pure white
  static const Color iosSurface = Color(0xFFF2F2F7); // light gray cards
  static const Color iosSurfaceHi = Color(0xFFE5E5EA); // elevated surface
  static const Color iosText = Color(0xFF1C1C1E); // near-black
  static const Color iosTextDim = Color(0xFF8E8E93); // system gray
  static const Color iosDivider = Color(0x1F3C3C43); // hairline border 12%
  static const Color iosAccent = Color(0xFF007AFF); // iOS system blue
  static const Color iosAccent2 = Color(0xFF34C759); // iOS system green

  // Accents — gold family.
  static const Color goldBright = Color(0xFFF0DD9E); // highlight
  static const Color gold = Color(0xFFC9A650); // primary accent
  static const Color goldDeep = Color(0xFF8A6F33); // shadowed gold
  static const Color goldDay = Color(0xFF9A7820); // muted for day mode

  // Status — kept for API compat; mapped into gold language.
  static const Color alertRed = Color(0xFFC9A650); // was red → now gold
  static const Color alertRedDay = Color(0xFF9A7820);
  static const Color warnYellow = Color(0xFFF0DD9E); // was yellow → gold-bright
  static const Color warnYellowDay = Color(0xFFB8912E);
  static const Color okGreen =
      Color(0xFF9FBF70); // restrained sage for "success" only
  static const Color infoBlue = Color(0xFFC9A650);

  // ── Typography ────────────────────────────────────────────────────────
  /// Display — Playfair Display (serif, luxurious, editorial).
  /// Use for hero titles, H1, big numerics.
  static TextStyle display({
    required double size,
    FontWeight weight = FontWeight.w900,
    Color? color,
    double letterSpacing = -0.01,
    FontStyle? fontStyle,
  }) =>
      GoogleFonts.playfairDisplay(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        fontStyle: fontStyle,
        height: 1.05,
      );

  /// Serif italic — Cormorant Garamond (editorial, elegant, taglines).
  static TextStyle serif({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0.02,
    FontStyle fontStyle = FontStyle.italic,
  }) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        fontStyle: fontStyle,
        height: 1.3,
      );

  /// Body — Inter (clean sans-serif, for UI labels, descriptions).
  static TextStyle body({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double letterSpacing = 0.01,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.35,
      );

  /// Mono — Inter with wide letter-spacing (for stats, counts, tiny labels).
  /// Aliased from body with wide tracking for consistency.
  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = 0.2,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.3,
      );

  // ── Spacing ───────────────────────────────────────────────────────────
  static const double sp1 = 4;
  static const double sp2 = 8;
  static const double sp3 = 12;
  static const double sp4 = 16;
  static const double sp5 = 20;
  static const double sp6 = 24;
  static const double sp8 = 32;
  static const double sp10 = 40;
  static const double sp12 = 48;
  static const double sp16 = 64;

  // ── Radius / clip ─────────────────────────────────────────────────────
  // Black & Gold favors SQUARE corners + thin borders over rounded pills.
  static const double rSharp = 0;
  static const double rSmall = 2;
  static const double rMed = 4;
  static const double rChip = 0;
  static const double cornerCutLg = 0; // disabled — gold borders are straight
  static const double cornerCutMd = 0;
  static const double cornerCutSm = 0;

  // ── Borders ───────────────────────────────────────────────────────────
  static const double borderThin = 1;
  static const double borderMed = 1; // finer in Black & Gold
  static const double borderThick = 2;

  // ── Durations ─────────────────────────────────────────────────────────
  static const Duration dFast = Duration(milliseconds: 120);
  static const Duration dNormal = Duration(milliseconds: 240);
  static const Duration dSlow = Duration(milliseconds: 420);
}

/// Theme extension. `context.hud.gold`, `context.hud.accent`, etc.
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

  /// Font family names (Phase 1 of iOS theme — see
  /// docs/superpowers/specs/2026-04-26-ios-theme-architecture-design.md).
  /// Existing widgets that hardcode 'Fraunces' continue to work; new/migrated
  /// widgets should read these tokens via `context.hud.displayFontFamily`.
  final String displayFontFamily;
  final String bodyFontFamily;
  final String monoFontFamily;

  /// Convenience gold aliases (same as accent/accent2 but clearer intent).
  Color get gold => accent;
  Color get goldBright => accent2;

  /// True for iOS White theme — widgets that need to render a different layout
  /// (e.g. wallpaper cards switch from "Ticket Stub" to clean iOS card) check
  /// this flag instead of comparing colors directly.
  bool get isIosStyle => bg == HudTokens.iosBg;

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

  @override
  HudTheme lerp(ThemeExtension<HudTheme>? other, double t) {
    if (other is! HudTheme) return this;
    return HudTheme(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHi: Color.lerp(surfaceHi, other.surfaceHi, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
      displayFontFamily: t < 0.5 ? displayFontFamily : other.displayFontFamily,
      bodyFontFamily: t < 0.5 ? bodyFontFamily : other.bodyFontFamily,
      monoFontFamily: t < 0.5 ? monoFontFamily : other.monoFontFamily,
    );
  }
}

extension HudThemeBuildContext on BuildContext {
  HudTheme get hud => Theme.of(this).extension<HudTheme>() ?? HudTheme.night;
}
