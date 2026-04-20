import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../core/design/hud_tokens.dart';

/// Memory-conscious wrapper around [CachedNetworkImage].
///
/// When a physical size hint is available (via [cacheWidth] / [cacheHeight]
/// OR [memCacheWidth] / [memCacheHeight]), the image is decoded at that size
/// instead of full resolution. Prevents a 4K wallpaper from occupying ~32 MB
/// of RAM just because it's being shown as a 150 px card.
class CachedWallpaperImage extends StatelessWidget {
  const CachedWallpaperImage({
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.maxDecodedWidth = 640,
    super.key,
  });

  final String imageUrl;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Hard cap on the width at which the image is decoded into memory.
  /// 640 px is enough for any card / grid thumbnail on a 1080 px screen
  /// (cards are at most ~half-screen). Full preview pages override to 1280.
  final int maxDecodedWidth;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final decodeWidth = (maxDecodedWidth * dpr).clamp(200, 2160).toInt();

    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      memCacheWidth: decodeWidth,
      maxWidthDiskCache: 1080,
      fadeInDuration: const Duration(milliseconds: 160),
      placeholder: (context, url) => Shimmer.fromColors(
        baseColor: HudTokens.nightSurface,
        highlightColor: HudTokens.nightSurfaceHi,
        child: Container(color: HudTokens.nightSurface),
      ),
      errorWidget: (context, url, error) => Container(
        color: HudTokens.nightSurface,
        child: Icon(
          Icons.broken_image,
          color: HudTokens.gold.withOpacity(0.3),
          size: 40,
        ),
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}
