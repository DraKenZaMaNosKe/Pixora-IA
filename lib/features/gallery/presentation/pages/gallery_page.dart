import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/wallpaper_providers.dart';
import '../widgets/wallpaper_card.dart';

class GalleryPage extends ConsumerWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpapersAsync = ref.watch(trendingWallpapersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PixoraIA'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: wallpapersAsync.when(
        data: (wallpapers) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.65,
          ),
          itemCount: wallpapers.length,
          itemBuilder: (context, index) => WallpaperCard(wallpaper: wallpapers[index]),
        ),
        error: (err, _) => Center(
          child: Text(
            'No pudimos cargar los wallpapers.\n${err.toString()}',
            textAlign: TextAlign.center,
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
