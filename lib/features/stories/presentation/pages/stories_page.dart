import 'package:flutter/material.dart';
import '../../../../core/design/hud_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/section_hero_banner.dart';
import '../../../../core/widgets/ticket_stub_card.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
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
            Icon(Icons.auto_stories, size: 64, color: context.hud.divider),
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
                Icon(Icons.auto_stories, size: 64, color: context.hud.divider),
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

        return Column(
          children: [
            SectionHeroBanner(
              items: stories
                  .take(5)
                  .map((story) => HeroBannerItem(
                        imageUrl: story.coverImageUrl,
                        title: story.title,
                        subtitle:
                            '${story.frames.length} frames \u00b7 Every ${story.intervalMinutes} min',
                        badge: story.category,
                      ))
                  .toList(),
              onTap: (i) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoryDetailPage(story: stories[i]),
                  )),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: stories.length,
                itemBuilder: (context, index) {
                  final story = stories[index];
                  final isActive = activeId == story.id;

                  final glowColor = context.hud.accent;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      height: 340,
                      child: TicketStubCard(
                        admitLabel: isActive ? 'PLAYING' : 'STORY',
                        title: story.title,
                        category:
                            '${story.frames.length} FRAMES · EVERY ${story.intervalMinutes} MIN',
                        isHighlighted: isActive,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoryDetailPage(story: story),
                          ),
                        ),
                        overlayTopLeft: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: context.hud.bg.withOpacity(0.6),
                            shape: BoxShape.circle,
                            border: Border.all(color: glowColor, width: 1),
                          ),
                          child: Icon(
                            isActive ? Icons.pause : Icons.play_arrow,
                            color: glowColor,
                            size: 18,
                          ),
                        ),
                        overlayTopRight: WallpaperStatsBar(
                          wallpaperId: 'story_${story.id}',
                          glowColor: glowColor,
                        ),
                        child: CachedWallpaperImage(
                          imageUrl: story.coverImageUrl,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
