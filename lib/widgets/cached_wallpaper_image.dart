import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class CachedWallpaperImage extends StatelessWidget {
  const CachedWallpaperImage({
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.borderRadius,
    super.key,
  });

  final String imageUrl;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      placeholder: (context, url) => Shimmer.fromColors(
        baseColor: const Color(0xFF1A1A2E),
        highlightColor: const Color(0xFF2A2A3E),
        child: Container(color: const Color(0xFF1A1A2E)),
      ),
      errorWidget: (context, url, error) => Container(
        color: const Color(0xFF1A1A2E),
        child: const Icon(Icons.broken_image, color: Colors.white24, size: 40),
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}
