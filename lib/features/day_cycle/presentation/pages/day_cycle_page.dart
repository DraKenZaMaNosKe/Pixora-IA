import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/section_hero_banner.dart';
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
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text('Failed to load themes', style: TextStyle(color: Colors.white70)),
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
          return const Center(
            child: Text('No day cycle themes available yet',
                style: TextStyle(color: Colors.white54)),
          );
        }
        return Column(
          children: [
            SectionHeroBanner(
              items: themes.take(5).map((theme) => HeroBannerItem(
                imageUrl: theme.previewUrl,
                title: theme.name,
                subtitle: theme.description,
                badge: 'DAY CYCLE',
                accentColor: const Color(0xFF00B4D8),
              )).toList(),
              onTap: (i) => Navigator.push(context, MaterialPageRoute(
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
                  itemBuilder: (context, index) => _DayCycleCard(theme: themes[index]),
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

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DayCycleDetailPage(theme: theme)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: isActive ? Border.all(color: Colors.greenAccent, width: 2) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              SizedBox(
                height: 200,
                width: double.infinity,
                child: Image.network(theme.previewUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF1A1A2E),
                    child: const Icon(Icons.image, color: Colors.white24, size: 48),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                    ),
                  ),
                ),
              ),
              // Stats bar
              Positioned(
                top: 8,
                right: isActive ? null : 8,
                left: isActive ? 8 : null,
                child: WallpaperStatsBar(
                  wallpaperId: 'daycycle_${theme.id}',
                  glowColor: Colors.deepPurple,
                ),
              ),
              if (isActive)
                Positioned(
                  top: 12, right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('ACTIVE',
                      style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              Positioned(
                bottom: 16, left: 16, right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(theme.name,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(theme.description,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(children: [
                      _PeriodChip(icon: Icons.wb_sunny, label: '6-12h', color: Colors.amber),
                      const SizedBox(width: 6),
                      _PeriodChip(icon: Icons.wb_cloudy, label: '12-18h', color: Colors.orange),
                      const SizedBox(width: 6),
                      _PeriodChip(icon: Icons.nights_stay, label: '18-21h', color: Colors.deepPurple),
                      const SizedBox(width: 6),
                      _PeriodChip(icon: Icons.dark_mode, label: '21-6h', color: Colors.indigo),
                    ]),
                  ],
                ),
              ),
            ],
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
  const _PeriodChip({required this.icon, required this.label, required this.color});

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
