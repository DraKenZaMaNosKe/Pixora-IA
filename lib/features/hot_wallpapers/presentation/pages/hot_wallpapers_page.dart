import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/widgets/section_hero_banner.dart';
import '../../../../core/widgets/stamped_foil_header.dart';
import '../../../../core/services/app_strings_service.dart';
import '../../../../core/services/live_wallpaper_catalog_service.dart';
import '../../../../core/widgets/aurora_waves_loading.dart';
import '../../../../core/widgets/watch_card_pieces.dart';
import '../../../realm/presentation/widgets/realm_grid_section.dart';
import '../../../wallpapers/data/wallpaper_adapter.dart';
import '../../../wallpapers/presentation/pages/wallpaper_viewer_hud_page.dart';
import '../../../wallpapers/presentation/widgets/category_chip_hud.dart';
import '../../data/models/live_wallpaper.dart';
import '../../providers/live_wallpaper_providers.dart';
import '../widgets/live_grid_card_overlay.dart';
import 'live_wallpaper_preview_page.dart';

/// Sub-section selector inside the LIVE tab. VIDEOS keeps the existing
/// catalog flow; SHADERS / CLOCKS render the static RealmCatalog grid
/// (Eduardo's pick 2026-05-31 — sub-sections instead of a 9th bottom nav).
enum _LiveSubTab { videos, shaders, clocks }

class HotWallpapersPage extends ConsumerStatefulWidget {
  const HotWallpapersPage({super.key});

  @override
  ConsumerState<HotWallpapersPage> createState() => _HotWallpapersPageState();
}

class _HotWallpapersPageState extends ConsumerState<HotWallpapersPage> {
  _LiveSubTab _subTab = _LiveSubTab.videos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SubTabBar(
          current: _subTab,
          onChanged: (t) => setState(() => _subTab = t),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    switch (_subTab) {
      case _LiveSubTab.shaders:
        return const RealmGridSection(clocksOnly: false);
      case _LiveSubTab.clocks:
        return const RealmGridSection(clocksOnly: true);
      case _LiveSubTab.videos:
        final catalogAsync = ref.watch(liveWallpaperCatalogProvider);
        return catalogAsync.when(
          loading: () => const _ShimmerLoading(),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: context.hud.accent, size: 48),
                const SizedBox(height: 12),
                Text('Failed to load live wallpapers',
                    style: TextStyle(color: context.hud.textDim)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(liveWallpaperCatalogProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Text('Coming soon!',
                    style: TextStyle(color: context.hud.textDim, fontSize: 16)),
              );
            }
            return _HotContent(items: items);
          },
        );
    }
  }
}

/// 3-segment toggle at the top of the LIVE tab. Pure visual — no Riverpod,
/// state lives in `_HotWallpapersPageState` so it resets when the user
/// switches bottom-nav tabs and comes back (intentional: each visit is
/// fresh, no stale sub-section memory across navigations).
class _SubTabBar extends StatelessWidget {
  final _LiveSubTab current;
  final ValueChanged<_LiveSubTab> onChanged;

  const _SubTabBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _segment(context, _LiveSubTab.videos, 'VIDEOS'),
          const SizedBox(width: 6),
          _segment(context, _LiveSubTab.shaders, 'SHADERS'),
          const SizedBox(width: 6),
          _segment(context, _LiveSubTab.clocks, 'CLOCKS'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, _LiveSubTab tab, String label) {
    final h = context.hud;
    final selected = tab == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(tab),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? h.accent : Colors.transparent,
            border: Border.all(
              color: selected ? h.accent : Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: selected
                  ? Colors.black
                  : Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}

class _HotContent extends ConsumerWidget {
  final List<LiveWallpaper> items;
  const _HotContent({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group by category
    final popular = items.take(8).toList();
    final categories = <String, List<LiveWallpaper>>{};
    for (final item in items) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }

    // Build the page as a CustomScrollView with slivers. This is the key
    // perf fix: la versión anterior usaba SingleChildScrollView + Column +
    // GridView(shrinkWrap, NeverScrollable). El shrinkWrap fuerza al
    // GridView a construir TODOS sus children al arranque, ignorando el
    // lazy. Con slivers, Flutter solo construye lo visible — escala a
    // miles de wallpapers sin sudar.
    final categoryEntries = categories.entries.toList();
    return RefreshIndicator(
      onRefresh: () async {
        LiveWallpaperCatalogService.instance.clearCache();
        ref.invalidate(liveWallpaperCatalogProvider);
        await Future.wait([
          ref.read(liveWallpaperCatalogProvider.future),
          AppStringsService.instance.refresh(),
        ]);
      },
      color: context.hud.accent,
      backgroundColor: context.hud.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Hero Banner ──────────────────────────────────────
          SliverToBoxAdapter(
            child: SectionHeroBanner(
              items: items
                  .take(5)
                  .map((item) => HeroBannerItem(
                        imageUrl: item.previewUrl,
                        title: item.name,
                        subtitle: item.description,
                        badge: item.category,
                        accentColor: context.hud.accent,
                      ))
                  .toList(),
              onTap: (i) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        LiveWallpaperPreviewPage(wallpaper: items[i]),
                  )),
            ),
          ),

          // ── HUD chips row — entry point to the WallpaperViewerHudPage
          // (Eduardo's pick 2026-05-17). Tap any chip opens the special
          // explorer with horizontal swipe + native ads. LIVE wallpapers
          // are adapted to Wallpaper via wallpaperFromLive() so the same
          // viewer renders both static AND live previews.
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: _LiveHudChipsRow(categories: categories),
          ),

          // ── Popular Now (horizontal row, ya era lazy) ────────
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(child: _buildSectionTitle('Popular Now', null)),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(child: _buildHorizontalRow(popular, context)),

          // ── Category sections (sliver grids lazy) ────────────
          for (final entry in categoryEntries) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(
                child: _buildSectionTitle(_formatCategory(entry.key), null)),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.65,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _LiveWallpaperCard(
                    item: entry.value[i],
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  childCount: entry.value.length,
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, VoidCallback? onSeeAll) {
    // Stamped Foil header (concept #01, Eduardo 2026-05-16) — same metal
    // stamp used in WALLPAPERS so the entire app speaks one section-header
    // language. iOS: dark text + Apple Blue glyph. B&G: gold foil + star.
    return Builder(builder: (context) {
      final hud = context.hud;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: StampedFoilHeader(
          label: title,
          trailing: onSeeAll == null
              ? null
              : GestureDetector(
                  onTap: onSeeAll,
                  child: Text(
                    'See All >',
                    style: TextStyle(
                      fontSize: 13,
                      color: hud.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
      );
    });
  }

  Widget _buildHorizontalRow(List<LiveWallpaper> items, BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _LiveWallpaperCard(
          item: items[i],
          width: 140,
          height: 220,
        ),
      ),
    );
  }

  String _formatCategory(String cat) {
    switch (cat.toUpperCase()) {
      case 'GAMING':
        return 'Gaming';
      case 'ANIME':
        return 'Anime & Manga';
      case 'SCIFI':
        return 'Sci-Fi & Space';
      case 'NATURE':
        return 'Nature & Ocean';
      case 'PIXEL':
        return 'Pixel Art';
      case 'HORROR':
        return 'Horror & Dark';
      case 'HEROES':
        return 'Superheroes';
      case 'CHILL':
        return 'Chill & Relaxing';
      default:
        return cat[0].toUpperCase() + cat.substring(1).toLowerCase();
    }
  }
}

// ── Live Wallpaper Card — Cinematic Strip (concept #01, 2026-05-16) ──
// Wallpaper 70% top + dark solid strip 30% bottom. Inside the strip live
// the NEW badge (solid Apple Blue / gold), the category title and the
// stats bar centered. LIVE/SHADER/3D mini tag sits top-right of the image,
// play icon top-center. Solves the contrast problem: Eduardo no quería el
// NEW translúcido sobre wallpapers saturados.
class _LiveWallpaperCard extends StatelessWidget {
  final LiveWallpaper item;
  final double width;
  final double height;

  const _LiveWallpaperCard({
    required this.item,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final isIos = h.isIosStyle;

    final stripColors = isIos
        ? [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.86),
            Colors.black.withValues(alpha: 0.95),
          ]
        : [
            const Color(0xFF070710).withValues(alpha: 0.0),
            const Color(0xFF070710).withValues(alpha: 0.86),
            const Color(0xFF070710).withValues(alpha: 0.97),
          ];

    return SizedBox(
      width: width.isFinite ? width : null,
      height: height.isFinite ? height : null,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LiveWallpaperPreviewPage(wallpaper: item),
          ),
        ),
        // 2026-06-14 — Ambient combo 2+3+4+5 (emoji rise + mini stamp +
        // heartbeat + ghost cursor) reacciona a statsEventStream remoto
        // por wallpaperId. Throttle 850ms per-card + IgnorePointer en los
        // overlays para no interferir con el tap del card.
        child: LiveGridCardOverlay(
          wallpaperId: item.id,
          borderRadius: 14,
          presenceAlignment: Alignment.bottomLeft,
          child: Container(
            decoration: BoxDecoration(
              color: h.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isIos
                    ? Colors.black.withValues(alpha: 0.06)
                    : HudTokens.gold.withValues(alpha: 0.20),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Wallpaper (full bleed) ───────────────────────────
                CachedNetworkImage(
                  imageUrl: item.previewUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  placeholder: (_, __) => const AuroraWavesLoading(),
                  errorWidget: (_, __, ___) => Container(
                    color: h.surface,
                    child: Icon(Icons.play_circle, color: h.accent, size: 40),
                  ),
                ),

                // ── LIVE / SHADER / 3D — holographic mini pill (consistency
                //    con el hero foil + Trading Card Holo). 2026-05-16.
                Positioned(
                  top: 6,
                  right: 6,
                  child: HoloFoilPill(
                    label: item.typeBadge,
                    size: HoloFoilPillSize.mini,
                  ),
                ),

                // ── Play icon + cinematic strip (positioned with real
                //    constraints, NOT widget.height which can be infinity in
                //    SliverGrid — that was causing the LIVE freeze bug
                //    2026-05-16). LayoutBuilder resolves to actual cell height.
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      final ch = constraints.maxHeight;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Play icon at ~18% from top
                          Positioned(
                            top: ch * 0.18,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.60),
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                          // Cinematic dark strip pinned to bottom 30%
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: ch * 0.30,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: stripColors,
                                  stops: const [0.0, 0.25, 1.0],
                                ),
                                border: isIos
                                    ? null
                                    : Border(
                                        top: BorderSide(
                                          color: HudTokens.goldBright
                                              .withValues(alpha: 0.18),
                                          width: 1,
                                        ),
                                      ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Row 1: Watch Cartouche pill (concept #04)
                                  Row(
                                    children: [
                                      if (item.effectiveBadge != null)
                                        WatchCartouchePill(
                                          label: item.effectiveBadge!,
                                        ),
                                    ],
                                  ),
                                  // Row 2: category/title
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      item.name.isEmpty
                                          ? item.category
                                          : item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: -0.01,
                                        height: 1.1,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.6),
                                            offset: const Offset(0, 1),
                                            blurRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Row 3: Activity Rings (concept #04) — likes/
                                  // views/downloads como 3 anillos conic-gradient
                                  // que fill-up al aparecer (social proof épico).
                                  Center(
                                    child: ActivityRings(
                                      wallpaperId: item.id,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Catalog loading skeleton ────────────────────────────────────────
// Mientras carga el catálogo del Storage, mostramos el mismo Aurora Waves
// que va dentro de los wallpapers, pero en card-shaped tiles. Así el
// loading se siente consistente con el resto de la app — nada de shimmer
// genérico Material.
class _ShimmerLoading extends StatelessWidget {
  const _ShimmerLoading();

  @override
  Widget build(BuildContext context) {
    Widget skelCard(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: context.hud.divider.withValues(alpha: 0.4), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: const AuroraWavesLoading(),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero banner placeholder
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(
              width: double.infinity,
              height: 200,
              child: AuroraWavesLoading(),
            ),
          ),
          const SizedBox(height: 28),
          // Section title placeholder
          Container(
            width: 180,
            height: 22,
            decoration: BoxDecoration(
              color: context.hud.surface,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 14),
          // Horizontal row placeholder (3 cards)
          SizedBox(
            height: 220,
            child: Row(
              children: List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: skelCard(140, 220),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          // Section title 2 placeholder
          Container(
            width: 140,
            height: 22,
            decoration: BoxDecoration(
              color: context.hud.surface,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 14),
          // Grid 2-column placeholder (4 cards visible)
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.65,
            children: List.generate(4, (_) => skelCard(0, 0)),
          ),
        ],
      ),
    );
  }
}

/// HUD chips row for LIVE — entry point to the WallpaperViewerHudPage.
/// Builds dynamic chips from the categories present in the LIVE catalog,
/// sorted by item count (most-populated first), max 6.
/// Tap converts that category's LiveWallpapers → Wallpaper via
/// `wallpaperFromLive()` and pushes the viewer.
class _LiveHudChipsRow extends StatefulWidget {
  const _LiveHudChipsRow({required this.categories});
  final Map<String, List<LiveWallpaper>> categories;

  @override
  State<_LiveHudChipsRow> createState() => _LiveHudChipsRowState();
}

class _LiveHudChipsRowState extends State<_LiveHudChipsRow> {
  String? _activeKey;

  void _openViewer(String catKey, List<LiveWallpaper> items) {
    setState(() => _activeKey = catKey);
    final adapted = items.map(wallpaperFromLive).toList();
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => WallpaperViewerHudPage(
          wallpapers: adapted,
          category: catKey.toUpperCase(),
        ),
      ),
    )
        .then((_) {
      if (mounted) setState(() => _activeKey = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sort categories by count, take top 6.
    final sorted = widget.categories.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final top = sorted.take(6).toList();
    return Container(
      color: const Color(0xFF02050A),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in top) ...[
              CategoryChipHud(
                label: entry.key,
                count: entry.value.length,
                active: _activeKey == entry.key,
                onTap: () => _openViewer(entry.key, entry.value),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}
