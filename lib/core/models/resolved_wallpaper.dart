/// Universal wallpaper view — same shape regardless of which catalog the
/// wallpaper actually lives in (Postgres dynamic_catalog, live_wallpaper
/// JSON, or canvas_scene catalog_index). Used by sections that mix
/// wallpapers from different sources, like the Events screen where one
/// event can include static + panoramic + live + canvas_scene items.
class ResolvedWallpaper {
  final String id;
  final String name;
  final String previewUrl;
  final WallpaperKind kind;

  /// The original typed object (Wallpaper / LiveWallpaper / CatalogIndexEntry)
  /// — needed when navigating to the type-specific preview page.
  final Object raw;

  const ResolvedWallpaper({
    required this.id,
    required this.name,
    required this.previewUrl,
    required this.kind,
    required this.raw,
  });

  /// Short label shown as a badge on cards inside heterogeneous grids
  /// (Events, Favorites, Search results). null = no badge needed.
  String? get kindBadge {
    switch (kind) {
      case WallpaperKind.liveVideo:
        return 'LIVE';
      case WallpaperKind.canvasScene:
        return '3D';
      case WallpaperKind.panoramic:
        return 'PANO';
      case WallpaperKind.staticImage:
        return null;
    }
  }
}

/// Distinct rendering / install paths each kind goes through.
/// - staticImage  → WallpaperPreviewPage, WallpaperManager.setBitmap
/// - panoramic    → WallpaperPreviewPage, treated as ultra-wide static
/// - liveVideo    → LiveWallpaperPreviewPage, MediaPlayer or frame-scrub
/// - canvasScene  → WallpaperPreviewPage with canvas_scene auto-resolve,
///                  CanvasSceneRenderer at runtime
enum WallpaperKind { staticImage, panoramic, liveVideo, canvasScene }
