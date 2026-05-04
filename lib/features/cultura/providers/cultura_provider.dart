import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/cultural_content.dart';
import '../../../core/services/catalog_index_service.dart';
import '../../wallpapers/data/models/wallpaper.dart';
import '../../wallpapers/providers/wallpaper_providers.dart';

/// Wallpapers visible in the "Cultura" section.
///
/// Rule: anything with a non-empty `cultural` block in either catalog
/// (Postgres dynamic_catalog OR catalog_index JSON) shows up here
/// automatically. Adding a new mythological wallpaper requires zero APK
/// rebuild — just upload the wallpaper + attach the cultural metadata
/// via tools/wallpapers/add_cultural_data.py and bump the catalog index
/// version. The next app launch picks it up.
///
/// To EXCLUDE a wallpaper that has cultural data (e.g. Iah Egyptian which
/// has its own ARCANO section), add its id to `_excludedFromCultura`.
const _excludedFromCultura = <String>{
  'iah_egyptian_giza', // has its own ARCANO/lunar calendar section
};

final culturaWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final all = await ref.watch(catalogProvider.future);
  final byId = <String, Wallpaper>{for (final w in all) w.id: w};
  final result = <Wallpaper>[];

  // dynamic_catalog wallpapers with cultural data
  for (final w in all) {
    if (_excludedFromCultura.contains(w.id)) continue;
    if (w.cultural != null && w.cultural!.isNotEmpty) {
      result.add(w);
    }
  }
  // catalog_index canvas_scene entries with cultural data
  final scenes = await CatalogIndexService.instance.getItems();
  for (final e in scenes) {
    if (_excludedFromCultura.contains(e.id)) continue;
    if (result.any((w) => w.id == e.id)) continue;
    // Prefer dynamic_catalog version if it exists (richer fields)
    final richer = byId[e.id];
    if (richer != null && richer.cultural != null) {
      result.add(richer);
      continue;
    }
    // Adapt the catalog_index entry — only include if it has cultural data
    final adapted = _wallpaperFromCatalogIndex(e);
    if (adapted.cultural != null && adapted.cultural!.isNotEmpty) {
      result.add(adapted);
    }
  }
  return result;
});

/// Adapt a CatalogIndexEntry into a Wallpaper, pulling cultural metadata
/// from the entry's raw bag.
Wallpaper _wallpaperFromCatalogIndex(CatalogIndexEntry e) {
  final previewFile = _basename(e.previewUrl);
  final imageFile = previewFile.replaceFirst('_preview.webp', '.webp');
  final raw = e.raw;
  return Wallpaper(
    id: e.id,
    name: e.titleFor('es'),
    description: raw['description']?.toString() ?? '',
    imageFile: imageFile,
    previewFile: previewFile,
    imageSize: (raw['image_size'] as num?)?.toInt() ?? 0,
    previewSize: (raw['preview_size'] as num?)?.toInt() ?? 0,
    glowColor: raw['glow_color']?.toString() ?? '#FFFFFF',
    category: e.category ?? 'CULTURA',
    badge: raw['badge']?.toString(),
    sortOrder: (raw['sort_order'] as num?)?.toInt() ?? 0,
    featured: e.featured,
    tags: e.tags,
    downloadCount: (raw['download_count'] as num?)?.toInt() ?? 0,
    createdAt: raw['created_at'] != null
        ? DateTime.tryParse(raw['created_at'].toString())
        : null,
    cultural: raw['cultural'] is Map<String, dynamic>
        ? CulturalContent.fromJson(raw['cultural'] as Map<String, dynamic>)
        : null,
  );
}

String _basename(String url) {
  final i = url.lastIndexOf('/');
  return i < 0 ? url : url.substring(i + 1);
}
