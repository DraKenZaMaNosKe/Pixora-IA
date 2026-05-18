import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../data/models/wallpaper.dart';

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

  // Google test banner ad unit (safe to use while _debugDisableAds is true
  // in AdService). Replace with the production banner unit ID when the rest
  // of AdMob is flipped on for Production.
  static const _testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  @override
  State<WallpaperViewerHudPage> createState() => _WallpaperViewerHudPageState();
}

class _WallpaperViewerHudPageState extends State<WallpaperViewerHudPage>
    with TickerProviderStateMixin {
  late final PageController _pageCtrl;
  late final AnimationController _scanlineCtrl;
  int _currentIndex = 0;
  late final List<_ViewerItem> _items;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    _pageCtrl = PageController(
      viewportFraction: 0.86,
      initialPage: _currentIndex,
    );
    _scanlineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
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
      if ((i + 1) % widget.adInterval == 0 &&
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
                _HudHeader(
                  category: widget.category,
                  authorName: _currentWallpaper?.authorName ?? 'Pixora Studio',
                  credits: 10, // TODO: wire CreditService.instance.balance
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _items.length,
                    onPageChanged: (i) => setState(() => _currentIndex = i),
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
                const _ActionRow(),
                _BannerAdHost(
                  adUnitId: WallpaperViewerHudPage._testBannerAdUnitId,
                ),
              ],
            ),
            // Animated scanline overlay for HUD feel (subtle)
            IgnorePointer(
              ignoring: true,
              child: AnimatedBuilder(
                animation: _scanlineCtrl,
                builder: (_, __) {
                  final y = _scanlineCtrl.value * viewportH;
                  return Positioned(
                    top: y,
                    left: 0,
                    right: 0,
                    height: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            WallpaperViewerHudPage.cyan.withValues(alpha: 0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.wallpaper});
  final Wallpaper? wallpaper;

  @override
  Widget build(BuildContext context) {
    // Placeholder stats — wire to wallpaper_stats Supabase later.
    final downloads = wallpaper?.downloadCount ?? 0;
    final downloadsStr = downloads >= 1000
        ? '${(downloads / 1000).toStringAsFixed(1)}K'
        : downloads.toString();
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
          _statChip('RATING', '4.8★'),
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
class _ActionRow extends StatelessWidget {
  const _ActionRow();

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
          _hudIcon(Icons.share_outlined),
          const SizedBox(width: 8),
          _hudIcon(Icons.favorite_border),
          const Spacer(),
          // ACQUIRE button — main CTA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: WallpaperViewerHudPage.amber,
              boxShadow: [
                BoxShadow(
                  color: WallpaperViewerHudPage.amber.withValues(alpha: 0.4),
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
          const Spacer(),
          _hudIcon(Icons.more_horiz),
        ],
      ),
    );
  }

  Widget _hudIcon(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        border: Border.all(color: WallpaperViewerHudPage.cyan, width: 1),
        color: WallpaperViewerHudPage.cyan.withValues(alpha: 0.04),
      ),
      child: Icon(icon, size: 14, color: WallpaperViewerHudPage.cyan),
    );
  }
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
    '6EE9F3D60B4F39A34BA3308FE533F24F', // Samsung RF8X903KZ3K (Eduardo principal)
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
