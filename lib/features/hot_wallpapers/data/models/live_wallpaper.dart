import '../../../../core/constants/supabase_config.dart';
import '../../../../core/content/content_types.dart';
import '../../../../core/content/content_url_resolver.dart';
import '../../../../core/models/cultural_content.dart';

enum LiveWallpaperType { video, shader, image3d }

class LiveWallpaper {
  final String id;
  final String name;
  final String description;
  final String videoFile; // MP4 for Auto Play mode
  final String? exploreFile; // MP4 optimized for Explore mode (legacy)
  final String previewFile; // WebP preview thumbnail
  final int frameCount; // Number of pre-extracted frames for Explore
  final String? framesPath; // Supabase path to frames folder
  final bool exploreOnly; // true = no Auto Play, only Explore mode
  final int videoSize; // bytes
  final int previewSize;
  final String glowColor;
  final String category; // GAMING, ANIME, SCIFI, NATURE, PIXEL, HORROR
  final LiveWallpaperType type;
  final String? badge; // LIVE, 3D, NEW, HOT
  final int sortOrder;
  final List<String> tags;
  final int downloadCount;
  final String? createdAt;

  /// Optional editorial content for cultural/mythology wallpapers — rendered
  /// by `CodexDetailLayout` when present, otherwise the simple description
  /// view is used. Null for regular wallpapers (gaming, sci-fi, etc.).
  final CulturalContent? cultural;

  const LiveWallpaper({
    required this.id,
    required this.name,
    required this.description,
    required this.videoFile,
    this.exploreFile,
    required this.previewFile,
    this.frameCount = 0,
    this.framesPath,
    this.exploreOnly = false,
    required this.videoSize,
    required this.previewSize,
    required this.glowColor,
    required this.category,
    this.type = LiveWallpaperType.video,
    this.badge,
    this.sortOrder = 0,
    this.tags = const [],
    this.downloadCount = 0,
    this.createdAt,
    this.cultural,
  });

  String get videoUrl =>
      '${SupabaseConfig.storageBase}/wallpaper-videos/$videoFile';

  String get exploreUrl =>
      '${SupabaseConfig.storageBase}/wallpaper-videos/${exploreFile ?? videoFile}';

  /// Whether pre-extracted frames are available on server
  bool get hasRemoteFrames => frameCount > 0 && framesPath != null;

  /// URL for a specific frame image
  String frameUrl(int index) =>
      '${SupabaseConfig.storageBase}/wallpaper-videos/$framesPath/frame_${(index + 1).toString().padLeft(4, '0')}.jpg';

  String get previewUrl =>
      '${SupabaseConfig.storageBase}/wallpaper-videos/$previewFile';

  String get typeBadge {
    switch (type) {
      case LiveWallpaperType.video:
        return 'LIVE';
      case LiveWallpaperType.shader:
        return 'SHADER';
      case LiveWallpaperType.image3d:
        return '3D';
    }
  }

  factory LiveWallpaper.fromJson(Map<String, dynamic> json) {
    return LiveWallpaper(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      videoFile: json['videoFile'] as String? ?? '',
      exploreFile: json['exploreFile'] as String?,
      previewFile: json['previewFile'] as String? ?? '',
      frameCount: json['frameCount'] as int? ?? 0,
      framesPath: json['framesPath'] as String?,
      exploreOnly: json['exploreOnly'] as bool? ?? false,
      videoSize: json['videoSize'] as int? ?? 0,
      previewSize: json['previewSize'] as int? ?? 0,
      glowColor: json['glowColor'] as String? ?? '#FF4500',
      category: json['category'] as String? ?? 'MISC',
      type: _parseType(json['type'] as String?),
      badge: json['badge'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      downloadCount: json['downloadCount'] as int? ?? 0,
      createdAt: json['createdAt'] as String?,
      cultural: json['cultural'] is Map<String, dynamic>
          ? CulturalContent.fromJson(json['cultural'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Effective badge — returns the configured `badge` field UNLESS it's
  /// "NEW" and the wallpaper is older than 7 days, in which case it
  /// silently expires and returns null.
  ///
  /// This prevents stale "NEW" badges from sticking around forever on
  /// wallpapers we shipped months ago. The catalog JSON keeps `badge: NEW`
  /// for human convenience (so we don't have to remove it manually) but
  /// the UI auto-hides it based on createdAt.
  String? get effectiveBadge {
    final raw = badge;
    if (raw == null) return null;
    if (raw.toUpperCase() != 'NEW') return raw;
    final created = createdAt;
    if (created == null) return null; // No date → don't show NEW
    final createdDate = DateTime.tryParse(created);
    if (createdDate == null) return null;
    final age = DateTime.now().difference(createdDate);
    return age.inDays <= 7 ? raw : null;
  }

  /// Convert to unified ContentItem for ContentManager.
  ContentItem toContentItem({bool explore = false}) {
    return ContentItem(
      id: id,
      type: explore ? ContentType.liveVideoExplore : ContentType.liveVideo,
      remoteFile: explore ? (exploreFile ?? videoFile) : videoFile,
      bucket: ContentUrlResolver.wallpaperVideosBucket,
      previewFile: previewFile,
      name: name,
      metadata: {
        'glowColor': glowColor,
        'interactive': explore,
        'frameCount': frameCount,
        'framesPath': framesPath,
        'exploreFile': exploreFile,
        'category': category,
        // Pass video size so ContentCache invalidates a stale cached MP4
        // when the catalog republishes the same videoFile with new bytes.
        // Skip in explore mode (frame-by-frame download has its own logic).
        if (!explore) 'expectedSize': videoSize,
      },
    );
  }

  static LiveWallpaperType _parseType(String? type) {
    switch (type) {
      case 'shader':
        return LiveWallpaperType.shader;
      case '3d':
        return LiveWallpaperType.image3d;
      default:
        return LiveWallpaperType.video;
    }
  }
}
