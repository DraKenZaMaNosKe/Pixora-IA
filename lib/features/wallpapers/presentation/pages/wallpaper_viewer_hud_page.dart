import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/ad_service.dart';
import '../../../../core/services/credit_service.dart';
import '../../../../core/services/report_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/widgets/report_content_modal.dart';
import '../../data/models/wallpaper.dart';
import 'wallpaper_preview_page.dart';

/// HUD Wallpaper Viewer — Eduardo's pick (Concept #5 Neon HUD Professional,
/// 2026-05-17). Full-screen horizontal swipe viewer for a single category.
///
/// Visual:
/// - Black ink background with cyan/amber accents
/// - Header: ESC button (back) + "TARGET ACQUIRED" + credits pill
/// - Category chips row (current category highlighted)
/// - Target frame: corners marked in amber + cyan border around wallpaper
/// - Stats bar: rating + downloads + rarity (placeholder for now)
/// - Action row: share, like, ACQUIRE (download), overflow
/// - Banner ad real al bottom (AdMob test unit while in debug)
///
/// Mock native ad cards intercalated every [adInterval] wallpapers in the
/// PageView so users see ad-style cards while swiping. Production native
/// ads (real AdMob native) come in Phase 2.
///
/// Author info comes from [Wallpaper.authorName] (default 'Pixora Studio').
///
/// Theme-independent: uses hardcoded HUD palette regardless of the app's
/// active theme (B&G / Cream / iOS). This is the "special explorer".
class WallpaperViewerHudPage extends StatefulWidget {
  const WallpaperViewerHudPage({
    super.key,
    required this.wallpapers,
    required this.category,
    this.initialIndex = 0,
    this.adInterval = 5,
  });

  /// List of wallpapers to display in the viewer (already filtered by
  /// category by the caller).
  final List<Wallpaper> wallpapers;

  /// Display name of the selected category (shown in the chip row).
  /// E.g. 'TRENDING', 'ARTE', 'DARK'. Pass UPPERCASE.
  final String category;

  /// Which wallpaper to show first (defaults to 0).
  final int initialIndex;

  /// Every N wallpapers, insert a mock native ad card in the swipe sequence.
  /// Default 5. Set to a large number to effectively disable.
  final int adInterval;

  // ─── HUD palette ──────────────────────────────────────────────────────
  static const ink = Color(0xFF02050A);
  static const inkLayer = Color(0xFF0A1018);
  static const cyan = Color(0xFF00E5FF);
  static const cyanDeep = Color(0xFF0099B0);
  static const amber = Color(0xFFFFB400);
  static const amberDeep = Color(0xFFB07A00);
  static const bone = Color(0xFFE8EEF5);

  // Banner ad unit — follows AdService.useProductionAds so all three ad
  // formats flip together. Prod = Pixora_Banner_WallpaperViewer (2026-07-14).
  static const _prodBannerAdUnitId = 'ca-app-pub-6734758230109098/2960762292';
  static const _testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
  static String get _bannerAdUnitId =>
      AdService.useProductionAds ? _prodBannerAdUnitId : _testBannerAdUnitId;

  @override
  State<WallpaperViewerHudPage> createState() => _WallpaperViewerHudPageState();
}

class _WallpaperViewerHudPageState extends State<WallpaperViewerHudPage>
    with TickerProviderStateMixin {
  late final PageController _pageCtrl;
  late final AnimationController _scanlineCtrl;
  int _currentIndex = 0;
  late final List<_ViewerItem> _items;
  // Tracks which wallpapers the user liked DURING this viewer session.
  // Persisted to Supabase via WallpaperStatsService.toggleLike on each tap.
  // We track locally too so the heart icon flips immediately without a
  // round-trip to the server.
  final Set<String> _likedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    _pageCtrl = PageController(
      viewportFraction: 0.86,
      initialPage: _currentIndex,
    );
    // 2026-06-24 — Scanline antes corría con `.repeat()` permanente y daba
    // sensación de "imagen en carga eterna". Ahora corre UNA sola pasada
    // (~2.5s) tipo scan-and-reveal y se queda quieto. Si swipe a otra
    // página, .forward(from: 0) la dispara de nuevo en la nueva imagen.
    _scanlineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..forward();

    // 2026-06-13 fix — hidratar el set de likeados desde el cache local de
    // WallpaperStatsService (Hive). Sin esto, _likedIds arranca vacio cada
    // vez que abres el viewer → corazon outline → tap se interpreta como
    // LIKE nuevo aunque el usuario YA habia liked ese wallpaper → al darle
    // unlike accidental, el contador en Supabase baja a 0. Bug reportado
    // por Eduardo 2026-06-13.
    _hydrateLikesForVisibleItems();
  }

  /// Llena `_likedIds` con los wallpapers que el cache local marca como liked.
  /// Se llama en initState y cuando el indice cambia (por si Hive se hidrato
  /// despues — p.ej. usuario abre el viewer antes de que init() del service
  /// termine).
  void _hydrateLikesForVisibleItems() {
    final svc = WallpaperStatsService.instance;
    for (final item in _items) {
      if (item is _WallpaperItem) {
        if (svc.hasLiked(item.wallpaper.id)) {
          _likedIds.add(item.wallpaper.id);
        }
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _scanlineCtrl.dispose();
    super.dispose();
  }

  /// Build the interleaved list of wallpapers + ad placeholders.
  /// Pattern: every [adInterval] wallpapers, insert one _AdItem.
  List<_ViewerItem> _buildItems() {
    final out = <_ViewerItem>[];
    for (var i = 0; i < widget.wallpapers.length; i++) {
      out.add(_WallpaperItem(widget.wallpapers[i]));
      // Skip the interleaved native ad card when ads are globally suppressed
      // (debug/tester, active subscription, or Free Hour) — same gate the
      // interstitials use, so no ad surface leaks past it.
      if (!AdService.adsDisabledForUser &&
          (i + 1) % widget.adInterval == 0 &&
          i < widget.wallpapers.length - 1) {
        out.add(const _AdItem());
      }
    }
    return out;
  }

  Wallpaper? get _currentWallpaper {
    if (_currentIndex < 0 || _currentIndex >= _items.length) return null;
    final item = _items[_currentIndex];
    return item is _WallpaperItem ? item.wallpaper : null;
  }

  // ─── Action handlers ──────────────────────────────────────────────────

  Future<void> _onShare() async {
    final wp = _currentWallpaper;
    if (wp == null) return;
    HapticFeedback.lightImpact();
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '${wp.name} · Pixora IA\n${wp.previewUrl}',
          subject: wp.name,
        ),
      );
    } catch (e) {
      debugPrint('[ViewerHud] share failed: $e');
    }
  }

  Future<void> _onLike() async {
    final wp = _currentWallpaper;
    if (wp == null) return;
    HapticFeedback.lightImpact();
    // Optimistic toggle so the heart flips instantly.
    final wasLiked = _likedIds.contains(wp.id);
    setState(() {
      if (wasLiked) {
        _likedIds.remove(wp.id);
      } else {
        _likedIds.add(wp.id);
      }
    });
    try {
      await WallpaperStatsService.instance.toggleLike(wp.id);
    } catch (e) {
      debugPrint('[ViewerHud] toggleLike failed (revert): $e');
      // Rollback on failure so the UI matches server state.
      if (!mounted) return;
      setState(() {
        if (wasLiked) {
          _likedIds.add(wp.id);
        } else {
          _likedIds.remove(wp.id);
        }
      });
    }
  }

  Future<void> _onAcquire() async {
    final wp = _currentWallpaper;
    if (wp == null) return;
    HapticFeedback.mediumImpact();
    // Route to the existing Trading Card preview page which already has the
    // full apply flow (main screen / lock screen / both / live wallpaper
    // with effects + AdService gating + credit refund). Keeping both
    // experiences: HUD viewer for discovery/swipe, preview page for apply.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WallpaperPreviewPage(wallpaper: wp),
      ),
    );
  }

  Future<void> _onOverflow() async {
    final wp = _currentWallpaper;
    if (wp == null) return;
    HapticFeedback.lightImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WallpaperViewerHudPage.inkLayer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
        side: BorderSide(color: Color(0x3300E5FF), width: 1),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 3,
                color: WallpaperViewerHudPage.cyan.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '// ${wp.name.toUpperCase()}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                    color: WallpaperViewerHudPage.cyan,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _OverflowAction(
                icon: Icons.link,
                label: 'Copiar enlace',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: wp.previewUrl));
                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enlace copiado')),
                  );
                },
              ),
              _OverflowAction(
                icon: Icons.info_outline,
                label: 'Acerca del autor',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Por: ${wp.authorName}')),
                  );
                },
              ),
              _OverflowAction(
                icon: Icons.flag_outlined,
                label: 'Reportar contenido',
                onTap: () {
                  // 2026-06-21 — Antes era un mock que solo mostraba un
                  // snackbar fake "Reporte enviado · gracias" sin llamar
                  // al RPC. Eduardo lo notó en device cuando intentó
                  // reportar Quantum Atom y nada llegaba a la tabla.
                  // Ahora abre el modal real que sí persiste.
                  Navigator.of(sheetCtx).pop();
                  final wp = _currentWallpaper;
                  if (wp == null) return;
                  showReportContentModal(
                    context,
                    wallpaperId: wp.id,
                    kind: wp.isPanoramic
                        ? ReportableKind.panoramic
                        : ReportableKind.static_,
                    wallpaperMeta: {
                      'name': wp.name,
                      'category': wp.category,
                      'preview_url': wp.previewUrl,
                      'author': wp.authorName,
                      'reported_from': 'viewer_hud',
                    },
                  );
                },
                tint: WallpaperViewerHudPage.amber,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportH = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: WallpaperViewerHudPage.ink,
      body: SafeArea(
        child: Stack(
          children: [
            // Faint radial glow background
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.4),
                    radius: 1.2,
                    colors: [
                      WallpaperViewerHudPage.cyan.withValues(alpha: 0.05),
                      WallpaperViewerHudPage.ink,
                    ],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                ListenableBuilder(
                  listenable: CreditService.instance,
                  builder: (context, _) => _HudHeader(
                    category: widget.category,
                    authorName:
                        _currentWallpaper?.authorName ?? 'Pixora Studio',
                    credits: CreditService.instance.balance,
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _items.length,
                    onPageChanged: (i) {
                      setState(() => _currentIndex = i);
                      // 2026-06-24 — re-dispara la scanline (single-pass)
                      // en la nueva imagen para mantener el efecto de
                      // scan-and-reveal en cada swipe.
                      _scanlineCtrl.forward(from: 0);
                      // Re-hidratar por si el service termino su init() despues
                      // que abrimos el viewer (race entre Hive.openBox y
                      // navegacion del usuario).
                      final wp = _currentWallpaper;
                      if (wp != null &&
                          WallpaperStatsService.instance.hasLiked(wp.id) &&
                          !_likedIds.contains(wp.id)) {
                        setState(() => _likedIds.add(wp.id));
                      }
                    },
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      if (item is _AdItem) {
                        return _MockNativeAdCard(scanline: _scanlineCtrl);
                      }
                      final wp = (item as _WallpaperItem).wallpaper;
                      return _TargetFrame(
                        wallpaper: wp,
                        active: i == _currentIndex,
                      );
                    },
                  ),
                ),
                _StatsBar(
                  wallpaper: _currentWallpaper,
                ),
                _ActionRow(
                  // null when on an ad card so the buttons disable.
                  onShare: _currentWallpaper != null ? _onShare : null,
                  onLike: _currentWallpaper != null ? _onLike : null,
                  onAcquire: _currentWallpaper != null ? _onAcquire : null,
                  onOverflow: _currentWallpaper != null ? _onOverflow : null,
                  liked: _currentWallpaper != null &&
                      _likedIds.contains(_currentWallpaper!.id),
                ),
                // Banner also consults the global gate — hidden in
                // debug/tester, for subscribers, and during Free Hour.
                if (!AdService.adsDisabledForUser)
                  _BannerAdHost(
                    adUnitId: WallpaperViewerHudPage._bannerAdUnitId,
                  ),
              ],
            ),
            // Animated scanline overlay for HUD feel (subtle)
            // Animated scanline overlay for HUD feel (subtle).
            // Positioned MUST be the direct child of Stack. Wrapping
            // AnimatedBuilder so its builder returns Positioned is a
            // ParentDataWidget violation — Stack sees IgnorePointer +
            // AnimatedBuilder as children, reads StackParentData on a
            // plain ParentData and throws hundreds of casts per frame.
            // Net effect: the viewer renders as a gray hole. Fix is to
            // wrap the whole subtree in Positioned.fill and use
            // Transform.translate to slide the scanline vertically.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: AnimatedBuilder(
                  animation: _scanlineCtrl,
                  builder: (_, __) {
                    final y = _scanlineCtrl.value * viewportH;
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Transform.translate(
                        offset: Offset(0, y),
                        child: SizedBox(
                          width: double.infinity,
                          height: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  WallpaperViewerHudPage.cyan
                                      .withValues(alpha: 0.3),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── HUD Header ────────────────────────────────────────────────────────────
class _HudHeader extends StatelessWidget {
  const _HudHeader({
    required this.category,
    required this.authorName,
    required this.credits,
    required this.onBack,
  });

  final String category;
  final String authorName;
  final int credits;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: WallpaperViewerHudPage.cyan.withValues(alpha: 0.02),
        border: const Border(
          bottom: BorderSide(
            color: Color(0x3300E5FF),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                '‹ ESC',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: WallpaperViewerHudPage.cyan,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ),
          const Spacer(),
          // Author block: small avatar + "BY · NAME"
          Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
            decoration: BoxDecoration(
              color: WallpaperViewerHudPage.cyan.withValues(alpha: 0.06),
              border: Border.all(
                color: WallpaperViewerHudPage.cyan.withValues(alpha: 0.25),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        WallpaperViewerHudPage.cyan,
                        WallpaperViewerHudPage.amber,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Center(
                    child: Text(
                      authorName.isNotEmpty ? authorName[0].toUpperCase() : 'P',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: WallpaperViewerHudPage.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    authorName,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: WallpaperViewerHudPage.bone,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(
                color: WallpaperViewerHudPage.amber,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '◆ $credits',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: WallpaperViewerHudPage.amber,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Target frame around the wallpaper ────────────────────────────────────
class _TargetFrame extends StatelessWidget {
  const _TargetFrame({required this.wallpaper, required this.active});

  final Wallpaper wallpaper;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: AnimatedScale(
        scale: active ? 1.0 : 0.94,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: Stack(
          children: [
            // Frame
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: WallpaperViewerHudPage.cyan,
                  width: 1,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: WallpaperViewerHudPage.cyan
                              .withValues(alpha: 0.3),
                          blurRadius: 20,
                        ),
                      ]
                    : [],
              ),
              padding: const EdgeInsets.all(6),
              child: ClipRect(
                child: CachedNetworkImage(
                  imageUrl: wallpaper.previewUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  // Card grande del viewer modal (~400px). Decodificar 600px.
                  memCacheWidth: 600,
                  placeholder: (_, __) => Container(
                    color: WallpaperViewerHudPage.inkLayer,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: WallpaperViewerHudPage.cyan,
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: WallpaperViewerHudPage.inkLayer,
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: WallpaperViewerHudPage.cyanDeep,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 4 corner accents in amber
            const Positioned(
              top: -2,
              left: -2,
              child: _Corner(top: true, left: true),
            ),
            const Positioned(
              top: -2,
              right: -2,
              child: _Corner(top: true, left: false),
            ),
            const Positioned(
              bottom: -2,
              left: -2,
              child: _Corner(top: false, left: true),
            ),
            const Positioned(
              bottom: -2,
              right: -2,
              child: _Corner(top: false, left: false),
            ),
            // ID + author overlay at the bottom of the frame
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Text(
                      'ID: ${wallpaper.id.substring(0, wallpaper.id.length.clamp(0, 8))}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: WallpaperViewerHudPage.cyan,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Text(
                      'AUTHOR\n${wallpaper.authorName.toUpperCase()}',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 7,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color:
                            WallpaperViewerHudPage.bone.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.top, required this.left});
  final bool top;
  final bool left;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        border: Border(
          top: top
              ? const BorderSide(color: WallpaperViewerHudPage.amber, width: 2)
              : BorderSide.none,
          bottom: !top
              ? const BorderSide(color: WallpaperViewerHudPage.amber, width: 2)
              : BorderSide.none,
          left: left
              ? const BorderSide(color: WallpaperViewerHudPage.amber, width: 2)
              : BorderSide.none,
          right: !left
              ? const BorderSide(color: WallpaperViewerHudPage.amber, width: 2)
              : BorderSide.none,
        ),
      ),
    );
  }
}

// ─── Stats bar (rating · downloads · rarity) ──────────────────────────────
/// 2026-06-13 — convertido de StatelessWidget a StatefulWidget para mostrar
/// el contador de LIKES en tiempo real. Escucha el statsStream del
/// WallpaperStatsService — cuando el cliente local (optimistic update) o
/// otro usuario via Realtime incrementa el like, este widget rebuilds.
class _StatsBar extends StatefulWidget {
  const _StatsBar({required this.wallpaper});
  final Wallpaper? wallpaper;

  @override
  State<_StatsBar> createState() => _StatsBarState();
}

class _StatsBarState extends State<_StatsBar> {
  StreamSubscription<Map<String, Map<String, int>>>? _sub;
  Map<String, int> _stats = const {'likes': 0, 'downloads': 0, 'views': 0};

  @override
  void initState() {
    super.initState();
    _refreshFromCache();
    // Suscripcion al stream global — emite tanto en optimistic update local
    // como en cambios via Supabase Realtime (otro usuario dio like).
    _sub = WallpaperStatsService.instance.statsStream.listen((all) {
      final wp = widget.wallpaper;
      if (wp == null || !mounted) return;
      final s = all[wp.id];
      if (s != null) setState(() => _stats = s);
    });
  }

  @override
  void didUpdateWidget(_StatsBar old) {
    super.didUpdateWidget(old);
    // Al cambiar de wallpaper (swipe en el PageView), refrescar al instante
    // desde el cache; el stream cubrira los updates posteriores.
    if (old.wallpaper?.id != widget.wallpaper?.id) _refreshFromCache();
  }

  void _refreshFromCache() {
    final wp = widget.wallpaper;
    if (wp == null) return;
    _stats = WallpaperStatsService.instance.getStats(wp.id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = widget.wallpaper?.downloadCount ?? 0;
    final downloadsStr = downloads >= 1000
        ? '${(downloads / 1000).toStringAsFixed(1)}K'
        : downloads.toString();
    final likes = _stats['likes'] ?? 0;
    final likesStr = likes >= 1000
        ? '${(likes / 1000).toStringAsFixed(1)}K'
        : likes.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0x2600E5FF), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _statChip('LIKES', likesStr),
          _statChip('DL', downloadsStr),
          _statChip('RARITY', _rarityFromCount(downloads)),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              color: WallpaperViewerHudPage.cyan.withValues(alpha: 0.55),
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: WallpaperViewerHudPage.amber,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _rarityFromCount(int dl) {
    if (dl > 5000) return 'LEGEND';
    if (dl > 1000) return 'EPIC';
    if (dl > 100) return 'RARE';
    return 'COMMON';
  }
}

// ─── Action row (share · like · ACQUIRE · overflow) ──────────────────────
// Concept #02 "Holographic Glitch" (Eduardo 2026-05-18) — every ~5s each
// button briefly glitches: RGB chromatic aberration ghosts + jitter offset.
// A subtle scanline overlay constantly scrolls across the buttons.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    this.onShare,
    this.onLike,
    this.onAcquire,
    this.onOverflow,
    this.liked = false,
  });

  /// Tap handlers. Null = button rendered as disabled (greyed out).
  final VoidCallback? onShare;
  final VoidCallback? onLike;
  final VoidCallback? onAcquire;
  final VoidCallback? onOverflow;

  /// Whether the current wallpaper is in the user's favorites — shows a
  /// filled heart in amber when true.
  final bool liked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0x2600E5FF), width: 1),
        ),
      ),
      child: Row(
        children: [
          _GlitchEffect(
            phaseOffset: 0.00,
            child: _hudIcon(Icons.share_outlined, onShare),
          ),
          const SizedBox(width: 8),
          _GlitchEffect(
            phaseOffset: 0.22,
            child: _hudIcon(
              liked ? Icons.favorite : Icons.favorite_border,
              onLike,
              tint: liked ? WallpaperViewerHudPage.amber : null,
            ),
          ),
          const Spacer(),
          // ACQUIRE button — main CTA
          _GlitchEffect(
            phaseOffset: 0.55,
            child: GestureDetector(
              onTap: onAcquire,
              behavior: HitTestBehavior.opaque,
              child: Opacity(
                opacity: onAcquire == null ? 0.5 : 1.0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: WallpaperViewerHudPage.amber,
                    boxShadow: [
                      BoxShadow(
                        color:
                            WallpaperViewerHudPage.amber.withValues(alpha: 0.4),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded,
                          size: 16, color: WallpaperViewerHudPage.ink),
                      const SizedBox(width: 6),
                      Text(
                        'ACQUIRE',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.5,
                          color: WallpaperViewerHudPage.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          _GlitchEffect(
            phaseOffset: 0.78,
            child: _hudIcon(Icons.more_horiz, onOverflow),
          ),
        ],
      ),
    );
  }

  Widget _hudIcon(IconData icon, VoidCallback? onTap, {Color? tint}) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            border: Border.all(
              color: tint ?? WallpaperViewerHudPage.cyan,
              width: 1,
            ),
            color:
                (tint ?? WallpaperViewerHudPage.cyan).withValues(alpha: 0.04),
          ),
          child: Icon(
            icon,
            size: 14,
            color: tint ?? WallpaperViewerHudPage.cyan,
          ),
        ),
      ),
    );
  }
}

/// Holographic Glitch wrapper — concept #02 from hud_action_buttons_concepts
/// (Eduardo's pick 2026-05-18). Wraps any [child] with:
///   1. A subtle scanline that constantly scrolls across the child.
///   2. A brief "glitch burst" (~12% of cycle) where the child shows RGB
///      chromatic ghost copies (red shifted left, cyan shifted right) plus
///      a 1-2px positional jitter, recalling Cyberpunk 2077 / Detroit:BH UI.
///
/// [phaseOffset] (0..1) lets the parent stagger multiple buttons so they
/// never glitch in lockstep.
class _GlitchEffect extends StatefulWidget {
  const _GlitchEffect({
    required this.child,
    required this.phaseOffset,
  });

  final Widget child;
  final double phaseOffset;

  @override
  State<_GlitchEffect> createState() => _GlitchEffectState();
}

class _GlitchEffectState extends State<_GlitchEffect>
    with TickerProviderStateMixin {
  late final AnimationController _glitchCtrl;
  late final AnimationController _scanCtrl;

  // Glitch window — last 12% of each cycle shows the chromatic burst.
  static const _glitchStart = 0.88;

  // Ghost colors for RGB split (Cyberpunk red + electric cyan).
  static const _ghostRed = Color(0xFFFF003C);
  static const _ghostCyan = Color(0xFF00FFE0);

  @override
  void initState() {
    super.initState();
    _glitchCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _glitchCtrl.dispose();
    _scanCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_glitchCtrl, _scanCtrl]),
      builder: (_, __) {
        final t = (_glitchCtrl.value + widget.phaseOffset) % 1.0;
        final inGlitch = t > _glitchStart;
        // Drive per-frame jitter using a discrete frame counter so the
        // effect feels like staccato glitches, not smooth motion.
        Offset jitter = Offset.zero;
        bool showGhosts = false;
        double redOpacity = 0;
        double cyanOpacity = 0;
        if (inGlitch) {
          final glitchPhase = (t - _glitchStart) / (1.0 - _glitchStart);
          final frame = (glitchPhase * 6).floor();
          showGhosts = true;
          switch (frame) {
            case 0:
              jitter = const Offset(-1.5, 0);
              redOpacity = 0.55;
              cyanOpacity = 0.55;
              break;
            case 1:
              jitter = const Offset(1.5, 0);
              redOpacity = 0.7;
              cyanOpacity = 0.5;
              break;
            case 2:
              jitter = const Offset(0, -1);
              redOpacity = 0.4;
              cyanOpacity = 0.65;
              break;
            case 3:
              jitter = const Offset(0.5, 0);
              redOpacity = 0.65;
              cyanOpacity = 0.0;
              break;
            case 4:
              jitter = const Offset(2, 0.5);
              redOpacity = 0.55;
              cyanOpacity = 0.55;
              break;
            default:
              jitter = Offset.zero;
              redOpacity = 0.0;
              cyanOpacity = 0.3;
          }
        }
        return Transform.translate(
          offset: jitter,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (showGhosts)
                Transform.translate(
                  offset: const Offset(-2.5, 0),
                  child: Opacity(
                    opacity: redOpacity,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        _ghostRed,
                        BlendMode.srcATop,
                      ),
                      child: widget.child,
                    ),
                  ),
                ),
              if (showGhosts)
                Transform.translate(
                  offset: const Offset(2.5, 0),
                  child: Opacity(
                    opacity: cyanOpacity,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        _ghostCyan,
                        BlendMode.srcATop,
                      ),
                      child: widget.child,
                    ),
                  ),
                ),
              widget.child,
              // Scanline overlay — non-interactive
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ScanlineOverlayPainter(
                      progress: _scanCtrl.value,
                      color: WallpaperViewerHudPage.cyan,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// CustomPainter that draws a thin horizontal scanline (1-2px) sliding
/// vertically across the child. Subtle — used to reinforce the "screen
/// glitch" feeling without being distracting between glitch bursts.
class _ScanlineOverlayPainter extends CustomPainter {
  _ScanlineOverlayPainter({required this.progress, required this.color});

  /// 0..1 = top to bottom sweep, loops.
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final y = size.height * progress;
    // Soft band ~2px tall with quick fade.
    final rect = Rect.fromLTWH(0, y - 1, size.width, 2);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ScanlineOverlayPainter old) =>
      old.progress != progress || old.color != color;
}

// ─── Mock native ad card (intercalated in PageView) ──────────────────────
class _MockNativeAdCard extends StatelessWidget {
  const _MockNativeAdCard({required this.scanline});
  final AnimationController scanline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: WallpaperViewerHudPage.cyan.withValues(alpha: 0.2),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ad bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0866FF),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ads served by Meta · Sponsored',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const Icon(Icons.close, size: 14, color: Colors.white70),
                    ],
                  ),
                ),
                // Sponsor name
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SHEIN',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Set de camisa sin mangas con estampado',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF65676B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Product visual
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1BB76E), Color(0xFF0E6E42)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'SHOP NOW',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                // CTA
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF42B72A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        'SHOP NOW',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Banner ad host ──────────────────────────────────────────────────────
class _BannerAdHost extends StatefulWidget {
  const _BannerAdHost({required this.adUnitId});
  final String adUnitId;

  @override
  State<_BannerAdHost> createState() => _BannerAdHostState();
}

class _BannerAdHostState extends State<_BannerAdHost> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  /// SAME test device IDs as AdService._testDeviceIds — Samsung RF8X903KZ3K
  /// (Eduardo's primary). Critical: must be registered BEFORE load() so AdMob
  /// flags any served ad as 'test impression' even if the user accidentally
  /// taps it. Without this, a click on a real production ad unit could be
  /// counted as publisher self-click → suspension (lesson 2026-05-14: 29 days
  /// suspended, 2nd offense = permanent ban).
  ///
  /// Kept duplicated here (instead of importing AdService._testDeviceIds)
  /// because AdService._testDeviceIds is private. Update both lists together
  /// when adding a new test device.
  static const _testDeviceIds = <String>[
    '5B655AE2367833A19C9FD6920E3788F8', // Samsung RF8X903KZ3K (Eduardo principal)
    '6A586AD63419A924C043A270C880C788', // Huawei VNS-L53 G2R4C17516000149 (Eduardo)
  ];

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _initAndLoad();
    } else {
      _failed = true;
    }
  }

  Future<void> _initAndLoad() async {
    try {
      // Defense in depth: even though AdService.initialize() registers these
      // test device IDs at app startup, AdService may have skipped init if
      // _debugDisableAds was true. Re-apply here so the BannerAd we load
      // ALWAYS knows this device is a test device — clicks won't count.
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: _testDeviceIds,
          // Pin family-safe content (G rating) to filter out playables that
          // crashed mid-range Samsung devices (memory: tech_admob_v8_max_content_rating).
          maxAdContentRating: MaxAdContentRating.g,
        ),
      );
    } catch (e) {
      debugPrint('[BannerAdHost] init config failed (continuing): $e');
    }
    if (!mounted) return;
    _load();
  }

  void _load() {
    _ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('[BannerAdHost] failed to load: $err');
          ad.dispose();
          if (mounted) setState(() => _failed = true);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    if (!_loaded || _ad == null) {
      return Container(
        height: 50,
        color: WallpaperViewerHudPage.ink,
      );
    }
    return Container(
      color: WallpaperViewerHudPage.ink,
      alignment: Alignment.center,
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}

// ─── Overflow bottom sheet row ───────────────────────────────────────────
class _OverflowAction extends StatelessWidget {
  const _OverflowAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? WallpaperViewerHudPage.cyan;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: WallpaperViewerHudPage.bone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Item types ──────────────────────────────────────────────────────────
sealed class _ViewerItem {
  const _ViewerItem();
}

class _WallpaperItem extends _ViewerItem {
  const _WallpaperItem(this.wallpaper);
  final Wallpaper wallpaper;
}

class _AdItem extends _ViewerItem {
  const _AdItem();
}
