import '../../../core/services/catalog_index_service.dart';

/// Filters the global catalog_index for parallax-capable canvas_scenes.
///
/// A wallpaper qualifies if it's type=canvas_scene AND its tags include
/// 'parallax' or '3d'. We don't fetch each spec to check imageLayers
/// (too expensive) — we trust the tag convention.
class ParallaxCatalogService {
  ParallaxCatalogService._();
  static final instance = ParallaxCatalogService._();

  Future<List<CatalogIndexEntry>> getParallaxItems(
      {bool forceRefresh = false}) async {
    final all =
        await CatalogIndexService.instance.getItems(forceRefresh: forceRefresh);
    return all.where((e) {
      if (e.type != 'canvas_scene') return false;
      final t = e.tags.map((s) => s.toLowerCase()).toSet();
      return t.contains('parallax') || t.contains('3d');
    }).toList();
  }
}
