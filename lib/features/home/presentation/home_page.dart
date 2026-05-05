import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/hud_shapes.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/design/hud_widgets.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/credit_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../ai_generate/presentation/pages/ai_generate_page.dart';
import '../../favorites/presentation/favorites_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../stories/presentation/pages/stories_page.dart';
import '../../day_cycle/presentation/pages/day_cycle_page.dart';
import '../../hot_wallpapers/presentation/pages/hot_wallpapers_page.dart';
import '../../parallax_wallpapers/presentation/pages/parallax_wallpapers_page.dart';
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

  String get _title {
    final titles = [
      'PIXORA',
      if (!Platform.isIOS) 'LIVE',
      if (!Platform.isIOS) '3D',
      if (!Platform.isIOS) 'CULTURA',
      if (!Platform.isIOS) 'EVENTOS',
      if (!Platform.isIOS) 'AURA',
      if (!Platform.isIOS) 'ARCANO',
      if (!Platform.isIOS) 'STORIES',
      if (!Platform.isIOS) 'DAY CYCLE',
      if (!Platform.isIOS) 'TONES',
      if (!Platform.isIOS) 'AI CREATE',
      'FAVORITES',
      'SETTINGS',
    ];
    return titles[_currentIndex];
  }

  void _onAvatarTap() {
    // Both logged-in and guest open the profile page; the page itself shows
    // the right CTAs (Sign in with Google when guest, full data when user).
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PerfilPage()),
    );
  }

  void _showLoginSheet() {
    final h = context.hud;
    showModalBottomSheet(
      context: context,
      backgroundColor: h.surface,
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
              '// SYNC_CLOUD',
              style: HudTokens.display(
                  size: 12, color: h.accent, letterSpacing: 0.1),
            ),
            const SizedBox(height: HudTokens.sp3),
            Text(
              'SIGN IN TO PIXORA',
              style: HudTokens.display(
                  size: 20, color: h.text, letterSpacing: 0.02),
            ),
            const SizedBox(height: HudTokens.sp2),
            Text(
              'Sync favorites across devices and track your downloads',
              style: HudTokens.body(size: 13, color: h.textDim),
            ),
            const SizedBox(height: HudTokens.sp5),
            HudPrimaryButton(
              label: 'CONTINUE WITH GOOGLE',
              icon: Icons.g_mobiledata,
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await AuthService.instance.signInWithGoogle();
                if (success && mounted) {
                  setState(() {});
                  // Favorites auto-sync via FavoritesNotifier's auth listener.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '// WELCOME · FAVORITES SYNCED',
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
            Text(
              '> OPTIONAL · APP WORKS WITHOUT ACCOUNT',
              textAlign: TextAlign.center,
              style: HudTokens.mono(
                  size: 9, color: h.textDim, letterSpacing: 0.15),
            ),
          ],
        ),
      ),
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
          child: Padding(
            padding: const EdgeInsets.only(left: HudTokens.sp3),
            child: _PlusHaloAvatar(child: child),
          ),
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
        final inner = Container(
          padding: EdgeInsets.symmetric(
              horizontal: isIos ? 10 : HudTokens.sp3, vertical: 5),
          decoration: BoxDecoration(
            color: isIos ? Colors.white : h.surface,
            borderRadius: isIos ? BorderRadius.circular(12) : null,
            border: Border.all(color: h.accent, width: isIos ? 1.0 : 1.5),
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
              Icon(Icons.diamond, size: 14, color: h.accent2),
              const SizedBox(width: 5),
              Text('$credits',
                  style: HudTokens.mono(
                      size: 13,
                      weight: FontWeight.w700,
                      color: h.text,
                      letterSpacing: isIos ? 0.0 : 0.05)),
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
    final h = context.hud;
    final transparent = _isWallpapersTab;
    // Over a transparent AppBar the hero image shows through. On iOS White
    // the dark text disappears against bright wallpapers — add a halo shadow
    // for legibility (B&G title shows over a dark hero so a soft black shadow
    // works for both themes when transparent).
    final List<Shadow>? titleShadows = transparent
        ? [
            Shadow(
              color: Colors.black.withValues(alpha: h.isIosStyle ? 0.55 : 0.7),
              blurRadius: 10,
              offset: const Offset(0, 1),
            ),
          ]
        : null;
    final Color iconColor = transparent && h.isIosStyle ? Colors.white : h.text;
    return AppBar(
      backgroundColor: transparent ? Colors.transparent : h.bg,
      elevation: 0,
      leading: _buildAvatar(),
      leadingWidth: 56,
      title: Text(
        _title,
        style: HudTokens.display(
          size: 18,
          color: transparent && h.isIosStyle ? Colors.white : h.text,
          letterSpacing: 0.04,
        ).copyWith(shadows: titleShadows),
      ),
      actions: [
        _buildCreditsBadge(),
        const SizedBox(width: HudTokens.sp2),
        if (_isWallpapersTab)
          IconButton(
            icon: Icon(Icons.search, color: iconColor, size: 22),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WallpaperSearchPage(),
                ),
              );
            },
          ),
        const SizedBox(width: HudTokens.sp1),
      ],
    );
  }

  Widget _buildBottomNav() {
    final h = context.hud;
    // Per-tab brand colors — each section gets its own accent on the active
    // pill (Soft Pastel Pill design picked 2026-04-29). Inactive icons stay
    // monochromatic h.textDim so the row reads quiet, then the active section
    // bursts into its own color.
    final items = <_NavItemData>[
      const _NavItemData(Icons.image_outlined, 'WALL', Color(0xFF3B82F6)),
      if (!Platform.isIOS)
        const _NavItemData(Icons.play_arrow_rounded, 'LIVE', Color(0xFFEF4444)),
      if (!Platform.isIOS)
        const _NavItemData(
            Icons.threed_rotation_rounded, '3D', Color(0xFF8B5CF6)),
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
    return Container(
      decoration: BoxDecoration(
        color: h.bg,
        border: Border(
          top: BorderSide(
            color: h.divider,
            width: h.isIosStyle ? 0.5 : 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: KeyedSubtree(
                    key: _navKeys[i],
                    child: _NavItem(
                      data: items[i],
                      active: _currentIndex == i,
                      onTap: () {
                        AnalyticsService.instance
                            .trackTabView(items[i].label.toLowerCase());
                        setState(() => _currentIndex = i);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: h.isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: h.bg,
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
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
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  final Color color;
  const _NavItemData(this.icon, this.label, this.color);
}

/// Soft Pastel Pill nav item.
///
/// Inactive: monochromatic — icon + label in `h.textDim`, no fill.
/// Active:   rounded pill with the section's brand color at ~14 % alpha,
///           icon + label go full color of the section. The active pill is
///           the only place color appears in the row, so the user instantly
///           sees both "where I am" and "what kind of section it is".
class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.data, required this.active, required this.onTap});
  final _NavItemData data;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final color = active ? data.color : h.textDim;
    final pillBg = active
        ? data.color.withValues(alpha: h.isIosStyle ? 0.14 : 0.18)
        : null;
    return InkWell(
      onTap: () {
        // Haptic feedback on tab tap.
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      splashColor: data.color.withValues(alpha: 0.18),
      highlightColor: data.color.withValues(alpha: 0.06),
      // Icon-only nav — labels removed because they overflow at 10 items.
      // The colored pill on the active tab is enough wayfinding.
      // SizedBox with fixed height stops the pill from stretching to fill
      // the entire parent (which made the active tab eat the whole screen).
      child: SizedBox(
        height: 44,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: AnimatedScale(
              scale: active ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Icon(data.icon, color: color, size: 22),
            ),
          ),
        ),
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
                gradient: SweepGradient(
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
