import 'package:flutter/material.dart';

/// Where a section is reachable from in the new "Vitrina + Perilla" navigation.
enum SectionPlacement {
  /// Appears in the Perilla dial (the 10 primary sections).
  dial,

  /// Lives under the "Más" menu (secondary content: Stories, Tones, AI Create).
  more,

  /// Reached from the floating top bar (the gear → Settings).
  topBar,
}

/// The app's home sections — the single source of truth that replaces the three
/// hand-synced parallel lists (`_pages`, `_titles`, `_NavItemData`) that used to
/// live in `home_page.dart` and had to be kept in sync by hand (the foot-gun the
/// nav redesign kills).
///
/// Order matches the legacy 14-tab index (0..13) so the existing `IndexedStack`
/// mapping stays 1:1 through the structural refactor (Release A). Do NOT reorder
/// without remapping the IndexedStack children in `home_page.dart`.
enum HomeSection {
  estaticos, // 0  (was WALL / WallpapersPage)
  live, // 1  (was LIVE / HotWallpapersPage)
  tresD, // 2  (was 3D / ParallaxWallpapersPage)
  amor, // 3  (was AMOR / AmorPage)
  cultura, // 4  (was CULT / CulturaPage)
  eventos, // 5  (was EVNT / EventosPage)
  aura, // 6  (was AURA / AuraPage)
  arcano, // 7  (was ARC / ArcanoPage)
  stories, // 8  (was STOR / StoriesPage)
  dayCycle, // 9  (was DAY / DayCyclePage)
  tones, // 10 (was TON / RingtonesPage)
  aiCreate, // 11 (was IA / AIGeneratePage)
  favoritos, // 12 (was FAV / FavoritesPage)
  settings, // 13 (was SET / SettingsPage)
}

/// Immutable metadata for a [HomeSection] — everything the shell, the dial and
/// analytics need, in one place.
@immutable
class HomeSectionMeta {
  const HomeSectionMeta({
    required this.section,
    required this.label,
    required this.kicker,
    required this.icon,
    required this.brandColor,
    required this.analyticsKey,
    required this.placement,
    this.iosVisible = false,
    this.heroCapable = false,
  });

  /// The section this metadata describes.
  final HomeSection section;

  /// Human title shown in the Vitrina hero / selector (e.g. "Estáticos").
  final String label;

  /// Small eyebrow above the title in the Vitrina hero (e.g. "FONDOS FIJOS").
  final String kicker;

  /// Icon for the dial option and the "Más" menu.
  final IconData icon;

  /// Brand accent carried over 1:1 from the old Ember nav. Doubles as the dial's
  /// live background tint when this section is previewed.
  final Color brandColor;

  /// Analytics `section` value. MUST match the pre-redesign values so the admin
  /// ENGAGEMENT dashboard stays continuous — see
  /// `AnalyticsService.instance.trackTabView(...)`.
  final String analyticsKey;

  /// Where the section is reachable from in the new navigation.
  final SectionPlacement placement;

  /// Visible on iOS. The reduced iOS nav keeps only Estáticos / Favoritos /
  /// Ajustes (honors the existing `if (!Platform.isIOS)` convention).
  final bool iosVisible;

  /// Gets the big Fraunces title block + Aplicar / Vista previa in the Vitrina.
  /// Non-hero sections (Aura, Favoritos) render bare content with reserved top
  /// padding instead.
  final bool heroCapable;
}

/// The single source of truth, in legacy-index order (0..13) so the existing
/// `IndexedStack` keeps working unchanged through Release A. The list index of
/// each entry equals its [HomeSection.index].
const List<HomeSectionMeta> kHomeSections = [
  HomeSectionMeta(
    section: HomeSection.estaticos,
    label: 'Estáticos',
    kicker: 'FONDOS FIJOS',
    icon: Icons.image_outlined,
    brandColor: Color(0xFF3B82F6),
    analyticsKey: 'wall',
    placement: SectionPlacement.dial,
    iosVisible: true,
    heroCapable: true,
  ),
  HomeSectionMeta(
    section: HomeSection.live,
    label: 'Live',
    kicker: 'VIDEO EN MOVIMIENTO',
    icon: Icons.play_arrow_rounded,
    brandColor: Color(0xFFEF4444),
    analyticsKey: 'live',
    placement: SectionPlacement.dial,
    heroCapable: true,
  ),
  HomeSectionMeta(
    section: HomeSection.tresD,
    label: '3D',
    kicker: 'PARALLAX INMERSIVO',
    icon: Icons.threed_rotation_rounded,
    brandColor: Color(0xFF8B5CF6),
    analyticsKey: '3d',
    placement: SectionPlacement.dial,
    heroCapable: true,
  ),
  HomeSectionMeta(
    section: HomeSection.amor,
    label: 'Amor',
    kicker: 'PAREJAS Y ROMANCE',
    icon: Icons.volunteer_activism_outlined,
    brandColor: Color(0xFFD93A3A),
    analyticsKey: 'amor',
    placement: SectionPlacement.dial,
    heroCapable: true,
  ),
  HomeSectionMeta(
    section: HomeSection.cultura,
    label: 'Cultura',
    kicker: 'ARTE Y RAÍCES',
    icon: Icons.menu_book_outlined,
    brandColor: Color(0xFFD9B14A),
    analyticsKey: 'cult',
    placement: SectionPlacement.dial,
    heroCapable: true,
  ),
  HomeSectionMeta(
    section: HomeSection.eventos,
    label: 'Eventos',
    kicker: 'FECHAS ESPECIALES',
    icon: Icons.celebration_outlined,
    brandColor: Color(0xFFE85A8C),
    analyticsKey: 'evnt',
    placement: SectionPlacement.dial,
    heroCapable: true,
  ),
  HomeSectionMeta(
    section: HomeSection.aura,
    label: 'Aura',
    kicker: 'AUDIO PARA TU MENTE',
    icon: Icons.spa_outlined,
    brandColor: Color(0xFF06B6D4),
    analyticsKey: 'aura',
    placement: SectionPlacement.dial,
    heroCapable: false,
  ),
  HomeSectionMeta(
    section: HomeSection.arcano,
    label: 'Arcano',
    kicker: 'MÍSTICO Y ZODIACO',
    icon: Icons.nights_stay_outlined,
    brandColor: Color(0xFFD4AF37),
    analyticsKey: 'arc',
    placement: SectionPlacement.dial,
    heroCapable: true,
  ),
  HomeSectionMeta(
    section: HomeSection.stories,
    label: 'Stories',
    kicker: 'HISTORIAS ANIMADAS',
    icon: Icons.auto_stories_outlined,
    brandColor: Color(0xFFF59E0B),
    analyticsKey: 'stor',
    placement: SectionPlacement.more,
    heroCapable: false,
  ),
  HomeSectionMeta(
    section: HomeSection.dayCycle,
    label: 'Day Cycle',
    kicker: 'CICLO DEL DÍA',
    icon: Icons.wb_twilight_outlined,
    brandColor: Color(0xFFEAB308),
    analyticsKey: 'day',
    placement: SectionPlacement.dial,
    heroCapable: true,
  ),
  HomeSectionMeta(
    section: HomeSection.tones,
    label: 'Tones',
    kicker: 'TONOS Y RINGTONES',
    icon: Icons.music_note_outlined,
    brandColor: Color(0xFFEC4899),
    analyticsKey: 'ton',
    placement: SectionPlacement.more,
    heroCapable: false,
  ),
  HomeSectionMeta(
    section: HomeSection.aiCreate,
    label: 'AI Create',
    kicker: 'CREA CON IA',
    icon: Icons.auto_awesome_outlined,
    brandColor: Color(0xFF10B981),
    analyticsKey: 'ia',
    placement: SectionPlacement.more,
    heroCapable: false,
  ),
  HomeSectionMeta(
    section: HomeSection.favoritos,
    label: 'Favoritos',
    kicker: 'TUS GUARDADOS',
    icon: Icons.favorite_outline,
    brandColor: Color(0xFFF43F5E),
    analyticsKey: 'fav',
    placement: SectionPlacement.dial,
    iosVisible: true,
    heroCapable: false,
  ),
  HomeSectionMeta(
    section: HomeSection.settings,
    label: 'Ajustes',
    kicker: 'CONFIGURACIÓN',
    icon: Icons.settings_outlined,
    brandColor: Color(0xFF64748B),
    analyticsKey: 'set',
    placement: SectionPlacement.topBar,
    iosVisible: true,
    heroCapable: false,
  ),
];

/// Metadata lookup. The registry is authored in [HomeSection.index] order, so
/// this is a direct index — an assertion guards the invariant in debug builds.
extension HomeSectionX on HomeSection {
  HomeSectionMeta get meta {
    final m = kHomeSections[index];
    assert(
        m.section == this, 'kHomeSections order must match HomeSection order');
    return m;
  }
}

/// Sections shown in the Perilla dial, in dial order (the 10 primary ones).
final List<HomeSectionMeta> kDialSections = kHomeSections
    .where((s) => s.placement == SectionPlacement.dial)
    .toList(growable: false);

/// Sections listed under the "Más" menu (Stories, Tones, AI Create).
final List<HomeSectionMeta> kMoreSections = kHomeSections
    .where((s) => s.placement == SectionPlacement.more)
    .toList(growable: false);
