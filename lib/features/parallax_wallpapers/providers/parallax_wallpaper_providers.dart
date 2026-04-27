import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../wallpapers/data/models/wallpaper.dart';
import '../../wallpapers/providers/wallpaper_providers.dart';

/// Returns the subset of dynamic_catalog wallpapers that are tagged as
/// '3d' or 'parallax'. Goku Genkidama qualifies (its tags include both).
/// New parallax wallpapers automatically appear here when uploaded with
/// the right tags — zero recompile.
final parallaxWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final all = await ref.watch(catalogProvider.future);
  final filtered = all.where((w) {
    final t = w.tags.map((s) => s.toLowerCase()).toSet();
    return t.contains('3d') || t.contains('parallax');
  }).toList();
  filtered.sort((a, b) {
    final ad = a.createdAt;
    final bd = b.createdAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return filtered;
});
