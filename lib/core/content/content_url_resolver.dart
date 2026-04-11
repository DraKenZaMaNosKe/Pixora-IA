import '../constants/supabase_config.dart';
import 'content_types.dart';

/// Resolves Supabase Storage URLs for any content item.
/// Single source of truth for bucket → URL mapping.
class ContentUrlResolver {
  ContentUrlResolver._();

  static String resolve(ContentItem item) =>
      '${SupabaseConfig.storageBase}/${item.bucket}/${item.remoteFile}';

  /// Resolve preview URL (same bucket, different file).
  static String? resolvePreview(ContentItem item) {
    if (item.previewFile == null) return null;
    return '${SupabaseConfig.storageBase}/${item.bucket}/${item.previewFile}';
  }

  /// Known bucket constants for quick reference.
  static const wallpaperImagesBucket = 'wallpaper-images';
  static const wallpaperVideosBucket = 'wallpaper-videos';
  static const auraAudioBucket = 'aura-audio';
}
