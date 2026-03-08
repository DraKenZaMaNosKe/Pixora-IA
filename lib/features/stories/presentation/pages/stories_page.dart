import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../providers/story_providers.dart';
import 'story_detail_page.dart';

class StoriesPage extends ConsumerWidget {
  const StoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(storyCatalogProvider);
    final activeId = ref.watch(activeStoryIdProvider);

    return catalogAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text('No stories available yet',
                style: TextStyle(color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(storyCatalogProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (stories) {
        if (stories.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_stories, size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                Text('Stories coming soon!',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 16)),
                const SizedBox(height: 4),
                Text('Wallpapers that tell a story',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3), fontSize: 13)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: stories.length,
          itemBuilder: (context, index) {
            final story = stories[index];
            final isActive = activeId == story.id;

            Color glowColor;
            try {
              final hex = story.glowColor.replaceFirst('#', '');
              glowColor = Color(int.parse('FF$hex', radix: 16));
            } catch (_) {
              glowColor = Colors.deepPurple;
            }

            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryDetailPage(story: story),
                ),
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                height: 200,
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
                      CachedWallpaperImage(imageUrl: story.coverImageUrl),
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
                          ),
                        ),
                      ),
                      // Info
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isActive) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: glowColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('PLAYING',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black)),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    story.title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${story.frames.length} frames · Every ${story.intervalMinutes} min',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Play icon
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            isActive ? Icons.pause : Icons.play_arrow,
                            color: glowColor,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
