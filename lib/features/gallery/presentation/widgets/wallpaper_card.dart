import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';

import '../../data/models/wallpaper.dart';

class WallpaperCard extends StatefulWidget {
  const WallpaperCard({required this.wallpaper, super.key});

  final Wallpaper wallpaper;

  @override
  State<WallpaperCard> createState() => _WallpaperCardState();
}

class _WallpaperCardState extends State<WallpaperCard> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.wallpaper.assetType == WallpaperAssetType.video) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.wallpaper.sourceUrl))
        ..setLooping(true)
        ..initialize().then((_) => setState(() {}))
        ..play();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);

    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.wallpaper.assetType == WallpaperAssetType.video)
            _controller?.value.isInitialized == true
                ? VideoPlayer(_controller!)
                : Image.network(widget.wallpaper.previewUrl, fit: BoxFit.cover)
          else
            Lottie.network(widget.wallpaper.sourceUrl, fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(.85)],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.wallpaper.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: -6,
                  children: widget.wallpaper.tags
                      .map((tag) => Chip(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            label: Text('#$tag'),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              onPressed: () {},
              icon: const Icon(Icons.favorite_border),
            ),
          ),
        ],
      ),
    );
  }
}
