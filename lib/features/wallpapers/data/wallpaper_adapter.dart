import '../../hot_wallpapers/data/models/live_wallpaper.dart';
import 'models/wallpaper.dart';

/// Adapter to expose [LiveWallpaper] instances through the [Wallpaper] type.
///
/// Used by [WallpaperViewerHudPage] so the SAME viewer renders both static
/// wallpapers AND live wallpapers without needing two parallel viewer pages.
/// Only fields needed by the viewer are mapped — animation/video playback
/// is NOT supported in the HUD viewer (it shows the static preview image).
///
/// The preview URL uses `customPreviewUrl` because LIVE wallpapers store
/// their preview file inside the `wallpaper-videos` bucket (handled by
/// `LiveWallpaper.previewUrl`), not the default `wallpaper-images` bucket
/// that `SupabaseConfig.imageUrl(previewFile)` resolves to.
Wallpaper wallpaperFromLive(LiveWallpaper l) {
  return Wallpaper(
    id: l.id,
    name: l.name,
    description: l.description,
    imageFile: l.videoFile, // not rendered as image; preserved for traceability
    previewFile: l.previewFile,
    imageSize: l.videoSize,
    previewSize: l.previewSize,
    glowColor: l.glowColor,
    category: l.category,
    badge: l.badge,
    sortOrder: l.sortOrder,
    tags: l.tags,
    downloadCount: l.downloadCount,
    createdAt: l.createdAt != null ? DateTime.tryParse(l.createdAt!) : null,
    cultural: l.cultural,
    // LIVE catalog doesn't yet ship author info — default to studio.
    // Phase 2: when LIVE catalog gets author_name in JSON, read from there.
    authorName: 'Pixora Studio',
    // LIVE previews live in a different bucket — override URL.
    customPreviewUrl: l.previewUrl,
  );
}
