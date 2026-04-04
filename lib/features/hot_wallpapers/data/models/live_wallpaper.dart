import '../../../../core/constants/supabase_config.dart';

enum LiveWallpaperType { video, shader, image3d }

class LiveWallpaper {
  final String id;
  final String name;
  final String description;
  final String videoFile;      // MP4 file in Supabase
  final String previewFile;    // WebP preview thumbnail
  final int videoSize;         // bytes
  final int previewSize;
  final String glowColor;
  final String category;       // GAMING, ANIME, SCIFI, NATURE, PIXEL, HORROR
  final LiveWallpaperType type;
  final String? badge;         // LIVE, 3D, NEW, HOT
  final int sortOrder;
  final List<String> tags;
  final int downloadCount;
  final String? createdAt;

  const LiveWallpaper({
    required this.id,
    required this.name,
    required this.description,
    required this.videoFile,
    required this.previewFile,
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
  });

  String get videoUrl =>
      '${SupabaseConfig.storageBase}/wallpaper-videos/$videoFile';

  String get previewUrl =>
      '${SupabaseConfig.storageBase}/wallpaper-videos/$previewFile';

  String get typeBadge {
    switch (type) {
      case LiveWallpaperType.video: return 'LIVE';
      case LiveWallpaperType.shader: return 'SHADER';
      case LiveWallpaperType.image3d: return '3D';
    }
  }

  factory LiveWallpaper.fromJson(Map<String, dynamic> json) {
    return LiveWallpaper(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      videoFile: json['videoFile'] as String? ?? '',
      previewFile: json['previewFile'] as String? ?? '',
      videoSize: json['videoSize'] as int? ?? 0,
      previewSize: json['previewSize'] as int? ?? 0,
      glowColor: json['glowColor'] as String? ?? '#FF4500',
      category: json['category'] as String? ?? 'MISC',
      type: _parseType(json['type'] as String?),
      badge: json['badge'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      downloadCount: json['downloadCount'] as int? ?? 0,
      createdAt: json['createdAt'] as String?,
    );
  }

  static LiveWallpaperType _parseType(String? type) {
    switch (type) {
      case 'shader': return LiveWallpaperType.shader;
      case '3d': return LiveWallpaperType.image3d;
      default: return LiveWallpaperType.video;
    }
  }
}
