import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/utils/color_utils.dart';
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
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text('Failed to load live wallpapers',
                style: TextStyle(color: Colors.white70)),
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
          return const Center(
            child: Text('Coming soon!',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
          );
        }
        return _HotContent(items: items);
      },
    );
  }
}

class _HotContent extends StatelessWidget {
  final List<LiveWallpaper> items;
  const _HotContent({required this.items});

  @override
  Widget build(BuildContext context) {
    // Group by category
    final popular = items.take(8).toList();
    final categories = <String, List<LiveWallpaper>>{};
    for (final item in items) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────
          const SizedBox(height: 8),
          _buildHeader(),

          // ── Warning banner ────────────────────────────────────
          const SizedBox(height: 12),
          _buildWarningBanner(),

          // ── Popular Now ───────────────────────────────────────
          const SizedBox(height: 20),
          _buildSectionTitle('Popular Now', null),
          const SizedBox(height: 12),
          _buildHorizontalRow(popular, context),

          // ── Category sections ─────────────────────────────────
          for (final entry in categories.entries) ...[
            const SizedBox(height: 24),
            _buildSectionTitle(_formatCategory(entry.key), null),
            const SizedBox(height: 12),
            _buildGrid(entry.value, context),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFF4500), Color(0xFFFF6B35), Color(0xFFFFD700)],
            ).createShader(bounds),
            child: const Text(
              'HOT',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'LIVE WALLPAPERS',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt, color: Colors.orange.shade300, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Animated wallpapers. Best for mid-high end devices. May use more battery.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade200,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, VoidCallback? onSeeAll) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See All >',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.orange.shade300,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
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

  Widget _buildGrid(List<LiveWallpaper> items, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.65,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _LiveWallpaperCard(
          item: items[i],
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }

  String _formatCategory(String cat) {
    switch (cat.toUpperCase()) {
      case 'GAMING': return 'Gaming';
      case 'ANIME': return 'Anime & Manga';
      case 'SCIFI': return 'Sci-Fi & Space';
      case 'NATURE': return 'Nature & Ocean';
      case 'PIXEL': return 'Pixel Art';
      case 'HORROR': return 'Horror & Dark';
      case 'HEROES': return 'Superheroes';
      case 'CHILL': return 'Chill & Relaxing';
      default: return cat[0].toUpperCase() + cat.substring(1).toLowerCase();
    }
  }
}

// ── Live Wallpaper Card ─────────────────────────────────────────────
class _LiveWallpaperCard extends StatelessWidget {
  final LiveWallpaper item;
  final double width;
  final double height;

  const _LiveWallpaperCard({
    required this.item,
    required this.width,
    required this.height,
  });

  Color get _glowColor => parseHexColor(item.glowColor, fallback: const Color(0xFFFF4500));

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveWallpaperPreviewPage(wallpaper: item),
        ),
      ),
      child: Container(
        width: width.isFinite ? width : null,
        height: height.isFinite ? height : null,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _glowColor.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Preview image
              CachedNetworkImage(
                imageUrl: item.previewUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: const Color(0xFF1A1A2E),
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF1A1A2E),
                  child: Icon(Icons.play_circle, color: _glowColor, size: 40),
                ),
              ),

              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.8),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),

              // Top row: badges left, stats right
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    // Type badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.type == LiveWallpaperType.video
                            ? Colors.red
                            : item.type == LiveWallpaperType.image3d
                                ? Colors.purple
                                : Colors.green,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        item.typeBadge,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Extra badge (HOT, NEW)
                    if (item.badge != null && item.badge != item.typeBadge) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B35),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          item.badge!,
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Play button (center)
              Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 24),
                ),
              ),

              // Bottom: stats + name
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WallpaperStatsBar(
                        wallpaperId: 'live_${item.id}',
                        glowColor: _glowColor,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shimmer Loading ─────────────────────────────────────────────────
class _ShimmerLoading extends StatelessWidget {
  const _ShimmerLoading();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Shimmer.fromColors(
            baseColor: const Color(0xFF1A1A2E),
            highlightColor: const Color(0xFF2A2A3E),
            child: Container(
              width: 200, height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: Row(
              children: List.generate(3, (i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Shimmer.fromColors(
                  baseColor: const Color(0xFF1A1A2E),
                  highlightColor: const Color(0xFF2A2A3E),
                  child: Container(
                    width: 140, height: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }
}
