import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/catalog_index_service.dart';
import '../../wallpapers/data/models/wallpaper.dart';
import '../../wallpapers/providers/wallpaper_providers.dart';

/// Returns the UNION of:
///   (a) dynamic_catalog wallpapers tagged '3d' or 'parallax', and
///   (b) catalog_index entries with type='canvas_scene'.
///
/// De-dup by id. When the same id exists in both catalogs, the
/// dynamic_catalog version wins because it carries richer Wallpaper fields
/// (description, glowColor, downloadCount, sortOrder).
///
/// Why both sources: dynamic_catalog holds the historical Wallpaper list
/// (used by the main grid + favorites); catalog_index is the newer unified
/// metadata file that drives canvas_scene installs (where the parallax
/// engine lives). Until those two are merged into one file, this provider
/// bridges them so any new parallax-capable scene shows up in the 3D tab
/// automatically — zero recompile, zero tag bookkeeping.
/// Ids hidden from the 3D tab without removing them from the underlying
/// catalogs. Existing installs keep working (install flow still resolves
/// the scene_id), they just stop appearing in the 3D listing.
/// User-curated 2026-04-29.
const _hiddenFromTab = <String>{
  'anime_drive',
  'carretera_nocturna',
};

final parallaxWallpapersProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final all = await ref.watch(catalogProvider.future);
  final byId = <String, Wallpaper>{for (final w in all) w.id: w};

  // Start with dynamic_catalog items already tagged 3d/parallax.
  final result = <String, Wallpaper>{};
  for (final w in all) {
    if (_hiddenFromTab.contains(w.id)) continue;
    final t = w.tags.map((s) => s.toLowerCase()).toSet();
    if (t.contains('3d') || t.contains('parallax')) {
      result[w.id] = w;
    }
  }

  // Union with catalog_index canvas_scenes. Prefer the dynamic_catalog
  // version when both exist (richer metadata).
  final scenes = await CatalogIndexService.instance.getItems();
  for (final e in scenes) {
    if (e.type != 'canvas_scene') continue;
    if (_hiddenFromTab.contains(e.id)) continue;
    if (result.containsKey(e.id)) continue;
    final richer = byId[e.id];
    result[e.id] = richer ?? _wallpaperFromCatalogIndex(e);
  }

  final merged = result.values.toList();
  merged.sort((a, b) {
    final ad = a.createdAt;
    final bd = b.createdAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return merged;
});

/// Adapt a CatalogIndexEntry into a Wallpaper for cases where the entry
/// has no matching dynamic_catalog row.
///
/// Static-image filenames follow the `pixora_<id>.webp` convention (verified
/// for the 7 launch-set canvas_scenes); previews are `pixora_<id>_preview.webp`.
/// Install flow auto-upgrades static IMAGE → canvas_scene by basename match
/// in WallpaperService._resolveCanvasSceneFromPath, so no special install
/// path is needed here.
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
    category: e.category ?? 'CANVAS_SCENE',
    badge: raw['badge']?.toString(),
    sortOrder: (raw['sort_order'] as num?)?.toInt() ?? 0,
    featured: e.featured,
    tags: e.tags,
    downloadCount: (raw['download_count'] as num?)?.toInt() ?? 0,
    createdAt: raw['created_at'] != null
        ? DateTime.tryParse(raw['created_at'].toString())
        : null,
  );
}

String _basename(String url) {
  final i = url.lastIndexOf('/');
  return i < 0 ? url : url.substring(i + 1);
}
