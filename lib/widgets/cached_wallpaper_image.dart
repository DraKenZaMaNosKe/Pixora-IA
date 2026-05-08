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
    this.maxDecodedWidth = 320,
    super.key,
  });

  final String imageUrl;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Hard cap on the LOGICAL width at which the image is decoded.
  /// Multiplied by devicePixelRatio at build time to get physical px.
  ///
  /// 320 logical = ~840 physical on a 2.625 dpr device. That's enough
  /// for any 3-column grid card (~360 logical px per card). Full preview
  /// pages override to 1080 to get crisp full-screen rendering.
  ///
  /// History: was 640 default which decoded to 1680 px on Samsung devices —
  /// each card bitmap weighed ~20 MB in GPU memory and 25 cards filled
  /// 500+ MB Graphics. That made playable AdMob ads stutter (Pixora was
  /// at 1 GB total PSS). Halved 2026-05-08 after dumpsys meminfo audit.
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
        baseColor: context.hud.surface,
        highlightColor: context.hud.surfaceHi,
        child: Container(color: context.hud.surface),
      ),
      errorWidget: (context, url, error) => Container(
        color: context.hud.surface,
        child: Icon(
          Icons.broken_image,
          color: context.hud.accent.withValues(alpha: 0.3),
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
