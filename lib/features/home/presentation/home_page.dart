import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/design/hud_shapes.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/design/hud_widgets.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/offline_indicator.dart';
import '../../../core/services/credit_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../ai_generate/presentation/pages/ai_generate_page.dart';
import '../../favorites/presentation/favorites_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../stories/presentation/pages/stories_page.dart';
import '../../day_cycle/presentation/pages/day_cycle_page.dart';
import '../../hot_wallpapers/presentation/pages/hot_wallpapers_page.dart';
import '../../parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart';
import '../../amor/presentation/amor_page.dart';
import '../../cultura/presentation/cultura_page.dart';
import '../../events/presentation/eventos_page.dart';
import '../../aura/presentation/pages/aura_page.dart';
import '../../arcano/presentation/arcano_page.dart';
import '../../ringtones/presentation/pages/ringtones_page.dart';
import '../../wallpapers/presentation/pages/wallpaper_search_page.dart';
import '../../wallpapers/presentation/pages/wallpapers_page.dart';
import '../../training/coach_mark_overlay.dart';
import '../../training/training_service.dart';
import '../../training/welcome_gift_sheet.dart';
import '../../../core/services/grace_pass_service.dart';
import '../../../core/services/wallpaper_resolver_service.dart';
import '../../wallpapers/data/models/wallpaper.dart';
import '../../wallpapers/presentation/pages/wallpaper_preview_page.dart';
import '../../perfil/presentation/perfil_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;
  bool _protectPromptOpen = false;

  /// Per-tab GlobalKeys for the coach-mark spotlights. The bottom nav has
  /// 13 tabs on Android right now (WALL/LIVE/3D/CULT/EVNT/AURA/ARC/STOR/
  /// DAY/TON/IA/FAV/SET); we allocate 16 for headroom in case future tabs
  /// land before someone remembers to bump this.
  late final List<GlobalKey> _navKeys =
      List.generate(16, (i) => GlobalKey(debugLabel: 'nav_$i'));

  OverlayEntry? _coachOverlay;

  /// Builds the tour steps from the current tab layout and shows the overlay.
  /// Public so Settings can re-trigger it via `homeKey.currentState?.showCoachMarks()`.
  void _showCoachMarks() {
    if (_coachOverlay != null) return; // already showing
    // Build steps in the same order as the bottom-nav items declared in
    // _buildBottomNav. Indices must match.
    final steps = _buildSteps();
    if (steps.isEmpty) return;
    AnalyticsService.instance.trackTutorialStarted();
    _coachOverlay = OverlayEntry(
      builder: (_) => CoachMarkOverlay(
        steps: steps,
        onFinish: (completed) {
          _coachOverlay?.remove();
          _coachOverlay = null;
          // After finishing the tour (whether completed or skipped), if the
          // welcome grace pass is still available offer the gift sheet —
          // this is the conversion remate that hooks the user with one
          // ad-free wallpaper of our best content (Volcano Dragon).
          if (mounted && GracePassService.instance.hasGrace) {
            _maybeShowWelcomeGift();
          }
        },
      ),
    );
    Overlay.of(context).insert(_coachOverlay!);
  }

  /// Resolves Volcano Dragon from the catalog_index and shows the welcome
  /// gift sheet. If resolution fails for any reason (network, missing entry),
  /// silently skips — better to lose the gift than crash the app.
  Future<void> _maybeShowWelcomeGift() async {
    try {
      final resolved =
          await WallpaperResolverService.instance.resolve('volcano_dragon');
      if (!mounted || resolved == null) return;
      AnalyticsService.instance.trackWelcomeGiftShown('volcano_dragon');
      await WelcomeGiftSheet.show(
        context,
        featuredName: 'Volcano Dragon',
        featuredSubtitle: 'Escena 3D · dragón ancestral en el volcán',
        featuredPreviewUrl: resolved.previewUrl,
        onAcceptGift: () {
          AnalyticsService.instance.trackWelcomeGiftRedeemed('volcano_dragon');
          Navigator.of(context).pop(); // close the sheet
          // Switch to the 3D tab so the user sees the wallpaper in context
          // when they return from the preview page.
          setState(() => _currentIndex = 2);
          // Navigate to Volcano Dragon's preview (its install flow respects
          // the grace pass via AdService).
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WallpaperPreviewPage(
              wallpaper: _adaptCanvasSceneForPreview(resolved.raw),
            ),
          ));
        },
        onLater: () {
          Navigator.of(context).pop(); // grace stays active for next install
        },
      );
    } catch (e) {
      debugPrint('[WelcomeGift] failed to show: $e');
    }
  }

  /// Adapt a CatalogIndexEntry (canvas_scene) into a Wallpaper for the
  /// shared WallpaperPreviewPage. Mirrors the same logic used by the
  /// EventDetailPage's _ResolvedTile.
  Wallpaper _adaptCanvasSceneForPreview(Object raw) {
    final entry = raw as dynamic; // CatalogIndexEntry has dynamic raw bag
    return Wallpaper(
      id: entry.id as String,
      name: entry.titleFor('es') as String,
      description: entry.raw['description']?.toString() ?? '',
      imageFile: (entry.previewUrl as String)
          .split('/')
          .last
          .replaceFirst('_preview.webp', '.webp'),
      previewFile: (entry.previewUrl as String).split('/').last,
      imageSize: 0,
      previewSize: 0,
      glowColor: entry.raw['glow_color']?.toString() ?? '#FFFFFF',
      category: (entry.category as String?) ?? 'CANVAS_SCENE',
      tags: (entry.tags as List).cast<String>(),
    );
  }

  List<CoachStep> _buildSteps() {
    // Bottom-nav declared order on Android (iOS hides several tabs):
    //   0 WALL · 1 LIVE · 2 3D · 3 CULT · 4 EVNT · 5 AURA
    //   6 ARC  · 7 STOR · 8 DAY · 9 TON · 10 IA · 11 FAV · 12 SET
    // We only point at the most user-visible ones so the tour stays short.
    final s = <CoachStep>[];
    void add(int idx, String title, String body) {
      final k = _navKeys[idx];
      if (k.currentContext == null) return; // tab not rendered (iOS hide)
      s.add(CoachStep(targetKey: k, title: title, body: body));
    }

    add(0, 'Wallpapers',
        'Aquí están todos los fondos. Toca cualquiera para verlo en grande y aplicarlo.');
    if (!Platform.isIOS) {
      add(1, 'LIVE', 'Wallpapers en movimiento — animaciones y efectos.');
      add(2, '3D', 'Profundidad real al inclinar tu teléfono.');
      add(3, 'Cultura',
          'Descubre mitología e historia con cada wallpaper. Lee el códice de cada dios.');
      add(4, 'Eventos',
          'Colecciones de temporada exclusivas: Día de Muertos, Navidad, San Valentín.');
      add(5, 'AURA', 'Sonidos para concentrarte, dormir o relajarte.');
      add(6, 'ARCANO', 'Tu calendario lunar personalizado por signo.');
    }
    return s;
  }

  @override
  void initState() {
    super.initState();
    CreditService.instance.addListener(_onCreditsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowProtectPrompt();
    });
    // Auto-fire the guided tour the first time HomePage builds (cold start
    // after onboarding + subscription pitch). Fires only if not seen yet.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await TrainingService.instance.init();
      if (!mounted) return;
      if (!TrainingService.instance.seen) {
        // Wait one more frame so all tab widgets are laid out
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showCoachMarks();
        });
      }
    });
  }

  @override
  void dispose() {
    CreditService.instance.removeListener(_onCreditsChanged);
    super.dispose();
  }

  void _onCreditsChanged() {
    if (!mounted) return;
    _maybeShowProtectPrompt();
  }

  void _maybeShowProtectPrompt() {
    if (_protectPromptOpen) return;
    if (!CreditService.instance.shouldShowProtectPrompt) return;
    _protectPromptOpen = true;
    CreditService.instance.markProtectPromptShown();
    _showProtectDiamondsSheet();
  }

  static final _pages = [
    const WallpapersPage(),
    if (!Platform.isIOS) const HotWallpapersPage(),
    if (!Platform.isIOS) const ParallaxWallpapersPage(),
    if (!Platform.isIOS) const AmorPage(),
    if (!Platform.isIOS) const CulturaPage(),
    if (!Platform.isIOS) const EventosPage(),
    if (!Platform.isIOS) const AuraPage(),
    if (!Platform.isIOS) const ArcanoPage(),
    if (!Platform.isIOS) const StoriesPage(),
    if (!Platform.isIOS) const DayCyclePage(),
    if (!Platform.isIOS) const RingtonesPage(),
    if (!Platform.isIOS) const AIGeneratePage(),
    const FavoritesPage(),
    const SettingsPage(),
  ];

  bool get _isWallpapersTab => _currentIndex == 0;

  // Title list allocated once at app start (platform check happens once).
  // Was being rebuilt on every _title getter call → wasted allocations
  // per setState. Review H-5 fix 2026-05-16.
  static final _titles = <String>[
    'Pixora',
    if (!Platform.isIOS) 'Live',
    if (!Platform.isIOS) '3D',
    if (!Platform.isIOS) 'Amor',
    if (!Platform.isIOS) 'Cultura',
    if (!Platform.isIOS) 'Eventos',
    if (!Platform.isIOS) 'Aura',
    if (!Platform.isIOS) 'Arcano',
    if (!Platform.isIOS) 'Stories',
    if (!Platform.isIOS) 'Day Cycle',
    if (!Platform.isIOS) 'Tones',
    if (!Platform.isIOS) 'AI Create',
    'Favoritos',
    'Ajustes',
  ];

  String get _title => _titles[_currentIndex];

  void _onAvatarTap() {
    // Both logged-in and guest open the profile page; the page itself shows
    // the right CTAs (Sign in with Google when guest, full data when user).
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PerfilPage()),
    );
  }

  void _showProtectDiamondsSheet() {
    final h = context.hud;
    final balance = CreditService.instance.balance;
    showModalBottomSheet(
      context: context,
      backgroundColor: h.surface,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(HudTokens.rSharp)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            HudTokens.sp6, HudTokens.sp5, HudTokens.sp6, HudTokens.sp6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '// PROTECT_DIAMONDS',
              style: HudTokens.display(
                  size: 12, color: h.accent, letterSpacing: 0.1),
            ),
            const SizedBox(height: HudTokens.sp3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.diamond, size: 34, color: h.accent2),
                const SizedBox(width: HudTokens.sp2),
                Text(
                  '$balance',
                  style: HudTokens.display(
                      size: 40, color: h.text, letterSpacing: -0.02),
                ),
              ],
            ),
            const SizedBox(height: HudTokens.sp2),
            Text(
              'YOU HIT 100 DIAMONDS',
              textAlign: TextAlign.center,
              style: HudTokens.display(
                  size: 18, color: h.text, letterSpacing: 0.02),
            ),
            const SizedBox(height: HudTokens.sp2),
            Text(
              'Sign in so they follow you across devices. If you wipe this '
              "phone, they're gone.",
              textAlign: TextAlign.center,
              style: HudTokens.body(size: 13, color: h.textDim),
            ),
            const SizedBox(height: HudTokens.sp5),
            HudPrimaryButton(
              label: 'PROTECT WITH GOOGLE',
              icon: Icons.shield_outlined,
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await AuthService.instance.signInWithGoogle();
                if (success && mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '// DIAMONDS PROTECTED',
                        style: HudTokens.mono(
                          size: 11,
                          color: Colors.white,
                          weight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                      backgroundColor: HudTokens.okGreen,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: HudTokens.sp3),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'MAYBE LATER',
                  style: HudTokens.mono(
                      size: 10, color: h.textDim, letterSpacing: 0.25),
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      _protectPromptOpen = false;
    });
  }

  Widget _buildAvatar() {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;
        final h = context.hud;
        // Bust the network image cache when the avatar URL changes between
        // accounts so we don't show user A's photo for user B.
        final url = auth.avatarUrl;
        final child = auth.isLoggedIn && url != null
            ? CircleAvatar(
                key: ValueKey('avatar:${auth.currentUser?.id ?? ''}'),
                radius: 16,
                backgroundImage: NetworkImage(url),
                backgroundColor: h.surface,
              )
            : CircleAvatar(
                radius: 16,
                backgroundColor: h.surface,
                child: Icon(Icons.person, size: 18, color: h.textDim),
              );
        return GestureDetector(
          onTap: _onAvatarTap,
          child: _PlusHaloAvatar(child: child),
        );
      },
    );
  }

  void _showCreditsSheet() {
    final h = context.hud;
    final credits = CreditService.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: h.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(HudTokens.rSharp)),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: credits,
        builder: (ctx, _) => Padding(
          padding: const EdgeInsets.fromLTRB(
              HudTokens.sp6, HudTokens.sp5, HudTokens.sp6, HudTokens.sp6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('// DIAMONDS_WALLET',
                  style: HudTokens.display(
                      size: 12, color: h.accent, letterSpacing: 0.1)),
              const SizedBox(height: HudTokens.sp4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.diamond, size: 38, color: h.accent2),
                  const SizedBox(width: HudTokens.sp2),
                  Text('${credits.balance}',
                      style: HudTokens.display(
                          size: 44, color: h.text, letterSpacing: -0.02)),
                ],
              ),
              const SizedBox(height: HudTokens.sp2),
              Center(
                child: Text('BALANCE',
                    style: HudTokens.mono(
                        size: 10, color: h.textDim, letterSpacing: 0.3)),
              ),
              const SizedBox(height: HudTokens.sp5),
              ClipPath(
                clipper: const CornerCutClipper(cut: HudTokens.cornerCutSm),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: HudTokens.sp4),
                  decoration: BoxDecoration(
                    color: h.surfaceHi,
                    border: Border.all(color: h.divider, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _creditStat('EARNED', '${credits.totalEarned}'),
                      Container(width: 1, height: 30, color: h.divider),
                      _creditStat('ADS', '${credits.adsWatched}'),
                      Container(width: 1, height: 30, color: h.divider),
                      _creditStat('PER AD', '+${CreditService.creditsPerAd}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: HudTokens.sp4),
              Text(
                '> WATCH ADS TO EARN DIAMONDS AUTOMATICALLY',
                textAlign: TextAlign.center,
                style: HudTokens.mono(
                    size: 10, color: h.textDim, letterSpacing: 0.15),
              ),
              const SizedBox(height: HudTokens.sp3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _creditStat(String label, String value) {
    final h = context.hud;
    return Column(
      children: [
        Text(value,
            style: HudTokens.display(
                size: 18, color: h.accent2, letterSpacing: -0.01)),
        const SizedBox(height: 2),
        Text(label,
            style:
                HudTokens.mono(size: 9, color: h.textDim, letterSpacing: 0.2)),
      ],
    );
  }

  Widget _buildCreditsBadge() {
    return ListenableBuilder(
      listenable: CreditService.instance,
      builder: (context, _) {
        final h = context.hud;
        final isIos = h.isIosStyle;
        final credits = CreditService.instance.balance;
        // Apple Premium #01: ios-surface bg, no border, ios-blue text + icon.
        // B&G keeps the gold border / dark surface treatment.
        const iosBlue = Color(0xFF0A84FF);
        final inner = Container(
          padding: EdgeInsets.symmetric(
              horizontal: isIos ? 10 : HudTokens.sp3, vertical: 5),
          decoration: BoxDecoration(
            color: isIos ? HudTokens.iosSurface : h.surface,
            borderRadius: isIos ? BorderRadius.circular(12) : null,
            border: isIos ? null : Border.all(color: h.accent, width: 1.5),
            boxShadow: isIos
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.diamond, size: 14, color: isIos ? iosBlue : h.accent2),
              const SizedBox(width: 5),
              // M07 — Credit Count-Up animado cuando el balance sube
              // (típicamente tras ver anuncio). Glow + bounce visible.
              _AnimatedCreditNumber(
                value: credits,
                style: HudTokens.mono(
                    size: 13,
                    weight: FontWeight.w700,
                    color: isIos ? iosBlue : h.text,
                    letterSpacing: isIos ? 0.0 : 0.05),
              ),
            ],
          ),
        );
        return GestureDetector(
          onTap: _showCreditsSheet,
          child: isIos
              ? inner
              : ClipPath(
                  clipper: const CornerCutClipper(cut: 6),
                  child: inner,
                ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return _HoloRibbonAppBar(
      title: _title,
      avatar: _buildAvatar(),
      creditsBadge: _buildCreditsBadge(),
      trailing: _isWallpapersTab
          ? IconButton(
              icon:
                  const Icon(Icons.search, color: Color(0xFFE8E6E0), size: 22),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WallpaperSearchPage(),
                  ),
                );
              },
            )
          : null,
    );
  }

  Widget _buildBottomNav() {
    // Ember Reactive — picked 2026-05-16. Always-dark warm charcoal nav
    // (`#1F1B17`), the active tab's brand color BLEEDS up from the bottom
    // as a radial ember; gold dust particles drift slowly; a 1px hairline
    // above the bar in the active color glows like neon; a Liquid Glass
    // Pill slides physically between tabs (300ms easeOutQuart) absorbing
    // the destination's brand color, icon white inside.
    final items = <_NavItemData>[
      const _NavItemData(Icons.image_outlined, 'WALL', Color(0xFF3B82F6)),
      if (!Platform.isIOS)
        const _NavItemData(Icons.play_arrow_rounded, 'LIVE', Color(0xFFEF4444)),
      if (!Platform.isIOS)
        const _NavItemData(
            Icons.threed_rotation_rounded, '3D', Color(0xFF8B5CF6)),
      // AMOR — volunteer_activism (mano ofreciendo corazón): distinto del
      // corazón simple de FAV para que no se confundan (Eduardo 2026-07-05).
      if (!Platform.isIOS)
        const _NavItemData(
            Icons.volunteer_activism_outlined, 'AMOR', Color(0xFFD93A3A)),
      if (!Platform.isIOS)
        const _NavItemData(Icons.menu_book_outlined, 'CULT', Color(0xFFD9B14A)),
      if (!Platform.isIOS)
        const _NavItemData(
            Icons.celebration_outlined, 'EVNT', Color(0xFFE85A8C)),
      if (!Platform.isIOS)
        const _NavItemData(Icons.spa_outlined, 'AURA', Color(0xFF06B6D4)),
      if (!Platform.isIOS)
        const _NavItemData(
            Icons.nights_stay_outlined, 'ARC', Color(0xFFD4AF37)),
      if (!Platform.isIOS)
        const _NavItemData(
            Icons.auto_stories_outlined, 'STOR', Color(0xFFF59E0B)),
      if (!Platform.isIOS)
        const _NavItemData(
            Icons.wb_twilight_outlined, 'DAY', Color(0xFFEAB308)),
      if (!Platform.isIOS)
        const _NavItemData(Icons.music_note_outlined, 'TON', Color(0xFFEC4899)),
      if (!Platform.isIOS)
        const _NavItemData(
            Icons.auto_awesome_outlined, 'IA', Color(0xFF10B981)),
      const _NavItemData(Icons.favorite_outline, 'FAV', Color(0xFFF43F5E)),
      const _NavItemData(Icons.settings_outlined, 'SET', Color(0xFF64748B)),
    ];
    return _EmberReactiveNav(
      items: items,
      currentIndex: _currentIndex,
      navKeys: _navKeys,
      onTap: (i) {
        AnalyticsService.instance.trackTabView(items[i].label.toLowerCase());
        setState(() => _currentIndex = i);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The Ember Reactive nav uses warm charcoal `#1F1B17`. The system
      // nav (3-button bar) must match it OR a grey strip appears between
      // the two. Always force the charcoal — matches what the Inkwell
      // header + Ember nav already use.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: const Color(0xFF1F1B17),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: h.bg,
        appBar: _buildAppBar(),
        body: IndexedStack(index: _currentIndex, children: _pages),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  final Color color;
  const _NavItemData(this.icon, this.label, this.color);
}

/// Ember Reactive bottom nav — picked 2026-05-16.
///
/// Visual identity:
///   • Always-dark warm charcoal bg `#1F1B17` (warm graphite, not B&G ink)
///   • The ACTIVE tab's brand color BLEEDS up from the bottom as a radial
///     ember (~28% alpha at base, fading to 0). Crossfades over 600ms when
///     the user switches tabs.
///   • 6 gold dust particles drift slowly upward (22s loop) above the bleed
///     — almost imperceptible, but they kill the dead-air feel.
///   • A 1px hairline sits above the bar in the active brand color with
///     8px glow — reads like neon piping.
///   • Glass surface `rgba(28,24,20,0.78)` over the bleed — the dark glass
///     lets the color leak through subtly.
///   • A Liquid Glass Pill slides PHYSICALLY between tabs (300ms
///     easeOutQuart) absorbing the destination tab's brand color. Icon
///     inside the pill is pure white; inactive icons are warm off-white
///     at 55% alpha.
///   • Active tab label fades in below the pill (mono, all-caps, 7px).
class _EmberReactiveNav extends StatefulWidget {
  const _EmberReactiveNav({
    required this.items,
    required this.currentIndex,
    required this.navKeys,
    required this.onTap,
  });

  final List<_NavItemData> items;
  final int currentIndex;
  final List<GlobalKey> navKeys;
  final ValueChanged<int> onTap;

  @override
  State<_EmberReactiveNav> createState() => _EmberReactiveNavState();
}

class _EmberReactiveNavState extends State<_EmberReactiveNav>
    with TickerProviderStateMixin {
  static const _bg = Color(0xFF1F1B17);
  static const _glass = Color(0xC71C1814); // 0.78
  static const _offWhite = Color(0xFFE8E6E0);
  static const _inactive = Color(0x8CE8E6E0); // 0.55

  late final AnimationController _dustCtrl;
  Color _bleedColor = const Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _dustCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
    _bleedColor = widget.items[widget.currentIndex].color;
  }

  @override
  void didUpdateWidget(covariant _EmberReactiveNav old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _bleedColor = widget.items[widget.currentIndex].color;
    }
  }

  @override
  void dispose() {
    _dustCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return Container(
      color: _bg,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (ctx, c) {
              final w = c.maxWidth;
              final tabW = w / n;
              return Stack(
                children: [
                  // Ember bleed — radial gradient from bottom-center in the
                  // active brand color. TweenAnimationBuilder crossfades on
                  // tab switch (600ms).
                  Positioned.fill(
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: _bleedColor),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, color, __) {
                        return IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0, 1.2),
                                radius: 1.1,
                                colors: [
                                  (color ?? _bleedColor)
                                      .withValues(alpha: 0.28),
                                  (color ?? _bleedColor).withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 0.85],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Gold dust particles drifting upward — wrapped in
                  // RepaintBoundary so the 60fps custom paint doesn't
                  // trigger a full bottom-nav repaint every frame.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _dustCtrl,
                          builder: (_, __) => CustomPaint(
                            painter:
                                _GoldDustPainter(progress: _dustCtrl.value),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Glass overlay — dark warm translucent so bleed bleeds through
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(color: _glass),
                    ),
                  ),
                  // Neon hairline at the very top, in active color
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: _bleedColor),
                      duration: const Duration(milliseconds: 600),
                      builder: (_, color, __) {
                        final c = color ?? _bleedColor;
                        return Container(
                          height: 1,
                          decoration: BoxDecoration(
                            color: c,
                            boxShadow: [
                              BoxShadow(
                                color: c.withValues(alpha: 0.55),
                                blurRadius: 8,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // Liquid pill — slides between tabs, absorbing brand color
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutQuart,
                    left: widget.currentIndex * tabW + (tabW - 44) / 2,
                    top: 10,
                    width: 44,
                    height: 44,
                    child: IgnorePointer(
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: _bleedColor),
                        duration: const Duration(milliseconds: 300),
                        builder: (_, color, __) {
                          final c = color ?? _bleedColor;
                          return Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                center: const Alignment(-0.3, -0.3),
                                colors: [
                                  Color.lerp(c, Colors.white, 0.25)!,
                                  c,
                                  Color.lerp(c, Colors.black, 0.2)!,
                                ],
                                stops: const [0.0, 0.6, 1.0],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: c.withValues(alpha: 0.45),
                                  blurRadius: 14,
                                  spreadRadius: -2,
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // Tab row — icons sit ABOVE the pill so the active one
                  // appears inside the pill (white) and inactives sit on
                  // the dark glass (warm off-white at 55%).
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: KeyedSubtree(
                            key: widget.navKeys[i],
                            child: _EmberTab(
                              data: widget.items[i],
                              active: widget.currentIndex == i,
                              activeColor: _offWhite, // unused on active
                              inactiveColor: _inactive,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onTap(i);
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmberTab extends StatelessWidget {
  const _EmberTab({
    required this.data,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final _NavItemData data;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: data.color.withValues(alpha: 0.15),
      highlightColor: data.color.withValues(alpha: 0.05),
      child: SizedBox(
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedScale(
              scale: active ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Icon(
                data.icon,
                size: 22,
                color: active ? Colors.white : inactiveColor,
              ),
            ),
            // Active label fades in below the pill
            Positioned(
              bottom: 4,
              child: AnimatedOpacity(
                opacity: active ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: Text(
                  data.label,
                  style: const TextStyle(
                    fontSize: 7,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8E6E0),
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 6 gold dust particles drifting slowly upward, fading at top.
/// Deterministic per-session so they don't shimmer randomly.
class _GoldDustPainter extends CustomPainter {
  final double progress; // 0..1 over 22s

  static final _particles = List.generate(6, (i) {
    final r = math.Random(i * 1009 + 7);
    return _Dust(
      x: r.nextDouble(),
      seed: r.nextDouble(),
      radius: 1.2 + r.nextDouble() * 1.0,
    );
  });

  _GoldDustPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      // Each particle has its own phase offset so they don't drift in sync
      final t = (progress + p.seed) % 1.0;
      final y = size.height * (1.0 - t); // bottom → top
      // Fade in at bottom, fade out at top
      final alpha = (math.sin(t * math.pi) * 0.5).clamp(0.0, 0.5);
      final x = p.x * size.width + math.sin(t * math.pi * 2 + p.seed * 6) * 4;
      canvas.drawCircle(
        Offset(x, y),
        p.radius,
        Paint()..color = const Color(0xFFD4AF37).withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GoldDustPainter old) =>
      old.progress != progress;
}

class _Dust {
  final double x, seed, radius;
  _Dust({required this.x, required this.seed, required this.radius});
}

/// ─────────────────────────────────────────────────────────────────────
///  Holographic Ribbon Header — picked 2026-05-16.
///
/// Unified header used in EVERY section. A 2px iridescent foil ribbon
/// runs across the top edge, shifting purple → cyan → silver → pink in
/// a 5s loop. The avatar wears an iridescent ring; the section title is
/// rendered via ShaderMask with the same foil gradient (Fraunces italic
/// mixed-case); the credits diamond pill gets an iridescent border too.
///
/// On the Wallpapers tab the bg is transparent so the hero banner shows
/// through; everywhere else it sits on the theme's `bg` color.
/// ─────────────────────────────────────────────────────────────────────
class _HoloRibbonAppBar extends StatefulWidget implements PreferredSizeWidget {
  const _HoloRibbonAppBar({
    required this.title,
    required this.avatar,
    required this.creditsBadge,
    this.trailing,
  });

  final String title;
  final Widget avatar;
  final Widget creditsBadge;
  final Widget? trailing;

  // Inkwell Dark Solid — `#1F1B17` warm charcoal, ALWAYS dark regardless
  // of theme (matches the Ember Reactive bottom nav for unified identity).
  static const _bg = Color(0xFF1F1B17);
  static const _brass = Color(0xFFD4AF37);

  // 56 (header) + 2 (ribbon)
  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  State<_HoloRibbonAppBar> createState() => _HoloRibbonAppBarState();
}

class _HoloRibbonAppBarState extends State<_HoloRibbonAppBar>
    with SingleTickerProviderStateMixin {
  // Single source of truth — see HudTokens.foilPalette.
  static const _holoColors = HudTokens.foilPalette;

  late final AnimationController _foilCtrl;

  @override
  void initState() {
    super.initState();
    _foilCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _foilCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: _HoloRibbonAppBar._bg,
      padding: EdgeInsets.only(top: topPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Holographic foil ribbon — 2px running across the top edge.
          // RepaintBoundary so the 60fps gradient shift doesn't cascade.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _foilCtrl,
              builder: (_, __) {
                final shift = _foilCtrl.value;
                return Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1 + shift * 2, 0),
                      end: Alignment(1 + shift * 2, 0),
                      colors: _holoColors,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE0B47A).withValues(alpha: 0.30),
                        blurRadius: 6,
                        spreadRadius: -1,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(
            height: 54,
            child: Row(
              children: [
                const SizedBox(width: 10),
                // Avatar with iridescent ring (the inner _PlusHaloAvatar
                // still keeps the gold breathing ring for Plus subscribers)
                _HoloRing(controller: _foilCtrl, child: widget.avatar),
                const SizedBox(width: 14),
                Expanded(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _foilCtrl,
                      builder: (_, __) {
                        final shift = _foilCtrl.value;
                        return ShaderMask(
                          shaderCallback: (rect) {
                            return LinearGradient(
                              begin: Alignment(-1 + shift * 2, 0),
                              end: Alignment(1 + shift * 2, 0),
                              colors: _holoColors,
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.srcIn,
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.fraunces(
                              fontSize: 22,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                              letterSpacing: -0.3,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (widget.trailing != null) ...[
                  widget.trailing!,
                  const SizedBox(width: 2),
                ],
                _HoloPillBorder(
                  controller: _foilCtrl,
                  child: widget.creditsBadge,
                ),
                // Offline indicator (Surface 1 · Cosmic Pulse) — solo
                // visible cuando no hay conexión. Aparece con bounce-in,
                // desaparece con sparkle-out. Cero espacio cuando online.
                const SizedBox(width: 8),
                const OfflineIndicator(),
                const SizedBox(width: 10),
              ],
            ),
          ),
          // Brass hairline below the bar — 0.5px at 30% alpha for a hint
          // of separation against the content below, never loud.
          Container(
            height: 0.5,
            color: _HoloRibbonAppBar._brass.withValues(alpha: 0.30),
          ),
        ],
      ),
    );
  }
}

/// Iridescent foil ring around the avatar — 1.5px gradient border
/// using a SweepGradient that slowly rotates so the foil "moves".
class _HoloRing extends StatelessWidget {
  const _HoloRing({required this.controller, required this.child});
  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary so the 60fps sweep rotation doesn't cascade into
    // the AppBar Row — review C-1 fix 2026-05-16.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          return Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                startAngle: 0,
                endAngle: math.pi * 2,
                transform: GradientRotation(controller.value * math.pi * 2),
                colors: HudTokens.foilPalette,
              ),
              boxShadow: [
                BoxShadow(
                  color: HudTokens.foilGlow.withValues(alpha: 0.25),
                  blurRadius: 8,
                  spreadRadius: -1,
                ),
              ],
            ),
            padding: const EdgeInsets.all(1.5),
            child: ClipOval(
              child: Center(child: child),
            ),
          );
        },
      ),
    );
  }
}

/// Pill wrapper that adds a 1px iridescent border around the existing
/// credits-diamond badge — keeps badge internals untouched.
class _HoloPillBorder extends StatelessWidget {
  const _HoloPillBorder({required this.controller, required this.child});
  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary — review C-1 fix 2026-05-16.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final shift = controller.value;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment(-1 + shift * 2, 0),
                end: Alignment(1 + shift * 2, 0),
                colors: HudTokens.foilPalette,
              ),
            ),
            padding: const EdgeInsets.all(1),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

// ── Plus-subscriber halo avatar ───────────────────────────────────
// Wraps the 32px avatar with a breathing gold ring when the user has an
// active Plus subscription. Listens to SubscriptionService so the halo
// appears/disappears reactively when status changes.
class _PlusHaloAvatar extends StatefulWidget {
  const _PlusHaloAvatar({required this.child});
  final Widget child;

  @override
  State<_PlusHaloAvatar> createState() => _PlusHaloAvatarState();
}

class _PlusHaloAvatarState extends State<_PlusHaloAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionService.instance,
      builder: (context, _) {
        final hasPlus = SubscriptionService.instance.status.hasAccess;
        if (!hasPlus) return widget.child;
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = _pulse.value; // 0..1..0 reversing
            final blur = 6.0 + 8.0 * t;
            final ringOpacity = 0.55 + 0.25 * t;
            return Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    HudTokens.goldDeep,
                    HudTokens.gold,
                    HudTokens.goldBright,
                    HudTokens.gold,
                    HudTokens.goldDeep,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: HudTokens.gold.withValues(alpha: ringOpacity * 0.5),
                    blurRadius: blur,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: widget.child,
            );
          },
        );
      },
    );
  }
}

/// M07 — Credit Count-Up animado. Cuando el balance sube (típicamente
/// después de ver anuncio), interpola el número y pulsa con glow. Bajadas
/// (spend) se aplican directo sin animación.
class _AnimatedCreditNumber extends StatefulWidget {
  const _AnimatedCreditNumber({required this.value, required this.style});
  final int value;
  final TextStyle style;

  @override
  State<_AnimatedCreditNumber> createState() => _AnimatedCreditNumberState();
}

class _AnimatedCreditNumberState extends State<_AnimatedCreditNumber>
    with SingleTickerProviderStateMixin {
  late int _displayed;
  late int _lastSeen;
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _displayed = widget.value;
    _lastSeen = widget.value;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void didUpdateWidget(_AnimatedCreditNumber old) {
    super.didUpdateWidget(old);
    if (widget.value != _lastSeen) {
      if (widget.value > _lastSeen) {
        _ctrl.forward(from: 0);
        _animateUp(_lastSeen, widget.value);
      } else {
        setState(() => _displayed = widget.value);
      }
      _lastSeen = widget.value;
    }
  }

  Future<void> _animateUp(int from, int to) async {
    final delta = to - from;
    final steps = delta.clamp(1, 30);
    for (var i = 1; i <= steps; i++) {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 35));
      if (!mounted) return;
      setState(() => _displayed = from + ((delta * i) ~/ steps));
    }
    if (mounted) setState(() => _displayed = to);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final pulse = t < 0.5 ? t * 2 : (1 - t) * 2;
        final scale = 1.0 + pulse * 0.18;
        final glow = pulse * 0.6;
        return Transform.scale(
          scale: scale,
          child: Text(
            '$_displayed',
            style: widget.style.copyWith(
              shadows: glow > 0.05
                  ? [
                      Shadow(
                        color: const Color(0xFFFFD66B).withValues(alpha: glow),
                        blurRadius: 12 * pulse,
                      ),
                    ]
                  : widget.style.shadows,
            ),
          ),
        );
      },
    );
  }
}
