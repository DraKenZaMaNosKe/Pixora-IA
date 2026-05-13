import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/widgets/section_hero_banner.dart';
import '../../../../core/widgets/ticket_stub_card.dart';
import '../../../../core/services/live_wallpaper_catalog_service.dart';
import '../../../../core/widgets/aurora_waves_loading.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../data/models/live_wallpaper.dart';
import '../../providers/live_wallpaper_providers.dart';
import 'live_wallpaper_preview_page.dart';

class HotWallpapersPage extends ConsumerWidget {
  const HotWallpapersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        await ref.read(liveWallpaperCatalogProvider.future);
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
    // NOTE: this is a stateless helper; we need a BuildContext to read the
    // theme. Wrap in Builder so context.hud resolves correctly without
    // having to thread context through the whole call chain.
    return Builder(builder: (context) {
      final hud = context.hud;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: hud.text, // adapts: white on B&G, dark on iOS White
              ),
            ),
            if (onSeeAll != null)
              GestureDetector(
                onTap: onSeeAll,
                child: Text(
                  'See All >',
                  style: TextStyle(
                    fontSize: 13,
                    color: hud.accent, // gold (B&G) or system blue (iOS)
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
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

// ── Live Wallpaper Card (Ticket Stub) ───────────────────────────────
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
    return SizedBox(
      width: width.isFinite ? width : null,
      height: height.isFinite ? height : null,
      child: TicketStubCard(
        admitLabel: 'LIVE',
        // Title + category hidden — distraction-free browsing.
        title: null,
        category: null,
        // Override the auto-derived lot number: title is null so the default
        // '().hashCode % 1000' would be 0 for every card. Derive from id so
        // each LIVE card gets its own unique N°.
        lotNumber: (item.id.hashCode.abs() % 1000).toString().padLeft(3, '0'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LiveWallpaperPreviewPage(wallpaper: item),
          ),
        ),
        overlayTopLeft: item.effectiveBadge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                color: context.hud.accent,
                child: Text(
                  item.effectiveBadge!.toUpperCase(),
                  style: HudTokens.mono(
                    size: 8,
                    weight: FontWeight.w700,
                    color: Colors.black,
                    letterSpacing: 0.15,
                  ),
                ),
              )
            : null,
        overlayTopRight: WallpaperStatsBar(
          wallpaperId: 'live_${item.id}',
          glowColor: context.hud.accent,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: item.previewUrl,
              fit: BoxFit.cover,
              memCacheWidth: 400,
              placeholder: (_, __) => const AuroraWavesLoading(),
              errorWidget: (_, __, ___) => Container(
                color: context.hud.surface,
                child: Icon(Icons.play_circle,
                    color: context.hud.accent, size: 40),
              ),
            ),
            // Play flourish in the center — thin gold circle, not a solid pill.
            Center(
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.hud.bg.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(color: context.hud.accent, width: 1),
                ),
                child: Icon(Icons.play_arrow_rounded,
                    color: context.hud.accent, size: 22),
              ),
            ),
          ],
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
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: const AuroraWavesLoading(),
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
