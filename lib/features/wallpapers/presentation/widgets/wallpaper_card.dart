import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../../../widgets/card_live_effect.dart';
import '../../../favorites/providers/favorites_provider.dart';
import '../../data/models/wallpaper.dart';
import '../pages/wallpaper_preview_page.dart';

class WallpaperCard extends ConsumerWidget {
  const WallpaperCard({required this.wallpaper, super.key});

  final Wallpaper wallpaper;

  Color _parseGlowColor() {
    try {
      final hex = wallpaper.glowColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(favoritesProvider).contains(wallpaper.id);
    final glowColor = _parseGlowColor();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
          ),
        );
      },
      child: CardLiveEffect(
        glowColor: glowColor,
        effectSeed: wallpaper.id.hashCode,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedWallpaperImage(imageUrl: wallpaper.previewUrl),
              // Gradient overlay
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                    stops: [0.5, 1.0],
                  ),
                ),
              ),
              // Badges row (top-left)
              Positioned(
                left: 8,
                top: 8,
                child: Row(
                  children: [
                    // Panoramic indicator
                    if (wallpaper.category == 'PANORAMIC')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: glowColor.withOpacity(0.6), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.panorama_wide_angle, size: 10, color: glowColor),
                            const SizedBox(width: 3),
                            Text(
                              'PANO',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: glowColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Regular badge (NEW, etc.)
                    if (wallpaper.badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: glowColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          wallpaper.badge!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Favorite button
              Positioned(
                right: 6,
                top: 6,
                child: GestureDetector(
                  onTap: () =>
                      ref.read(favoritesProvider.notifier).toggle(wallpaper.id),
                  child: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? Colors.redAccent : Colors.white70,
                    size: 22,
                  ),
                ),
              ),
              // Title hidden — let the image speak for itself
            ],
          ),
        ),
        ),
      ),
    );
  }
}
