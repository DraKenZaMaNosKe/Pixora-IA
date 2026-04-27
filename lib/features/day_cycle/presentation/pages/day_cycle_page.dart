import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/widgets/section_hero_banner.dart';
import '../../../../core/widgets/ticket_stub_card.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../providers/day_cycle_providers.dart';
import '../../data/models/day_cycle_theme.dart';
import 'day_cycle_detail_page.dart';

class DayCyclePage extends ConsumerWidget {
  const DayCyclePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(dayCycleCatalogProvider);

    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: context.hud.accent, size: 48),
            const SizedBox(height: 12),
            const Text('Failed to load themes',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(dayCycleCatalogProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (themes) {
        if (themes.isEmpty) {
          return Center(
            child: Text('No day cycle themes available yet',
                style: TextStyle(color: context.hud.textDim)),
          );
        }
        return Column(
          children: [
            SectionHeroBanner(
              items: themes
                  .take(5)
                  .map((theme) => HeroBannerItem(
                        imageUrl: theme.previewUrl,
                        title: theme.name,
                        subtitle: theme.description,
                        badge: 'DAY CYCLE',
                        accentColor: context.hud.accent,
                      ))
                  .toList(),
              onTap: (i) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DayCycleDetailPage(theme: themes[i]),
                  )),
              height: 0.35,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(dayCycleCatalogProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: themes.length,
                  itemBuilder: (context, index) =>
                      _DayCycleCard(theme: themes[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DayCycleCard extends ConsumerWidget {
  final DayCycleTheme theme;
  const _DayCycleCard({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeDayCycleIdProvider);
    final isActive = activeId == theme.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: 320,
        child: TicketStubCard(
          admitLabel: isActive ? 'ACTIVE' : 'DAY CYCLE',
          title: theme.name,
          category: theme.description.toUpperCase(),
          isHighlighted: isActive,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DayCycleDetailPage(theme: theme)),
          ),
          overlayTopRight: WallpaperStatsBar(
            wallpaperId: 'daycycle_${theme.id}',
            glowColor: context.hud.accent,
          ),
          child: Image.network(
            theme.previewUrl,
            fit: BoxFit.cover,
            cacheWidth: 400,
            errorBuilder: (_, __, ___) => Container(
              color: context.hud.surface,
              child: const Icon(Icons.image, color: Colors.white24, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _PeriodChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}
