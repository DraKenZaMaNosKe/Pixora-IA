import '../../../../core/constants/supabase_config.dart';
import '../../../../core/content/content_types.dart';
import '../../../../core/content/content_url_resolver.dart';
import '../../../../core/models/cultural_content.dart';

class Wallpaper {
  const Wallpaper({
    required this.id,
    required this.name,
    required this.description,
    required this.imageFile,
    required this.previewFile,
    required this.imageSize,
    required this.previewSize,
    required this.glowColor,
    required this.category,
    this.badge,
    this.sortOrder = 0,
    this.featured = false,
    this.tags = const [],
    this.downloadCount = 0,
    this.createdAt,
    this.cultural,
  });

  final String id;
  final String name;
  final String description;
  final String imageFile;
  final String previewFile;
  final int imageSize;
  final int previewSize;
  final String glowColor;
  final String category;
  final String? badge;
  final int sortOrder;
  final bool featured;
  final List<String> tags;
  final int downloadCount;
  final DateTime? createdAt;

  /// Optional editorial content for cultural / mythology wallpapers — when
  /// non-null, the detail page renders the Códice layout instead of the
  /// plain description view. Lives in the catalog so new entries ship
  /// without rebuilding the APK.
  final CulturalContent? cultural;

  String get previewUrl => SupabaseConfig.imageUrl(previewFile);
  String get fullImageUrl => SupabaseConfig.imageUrl(imageFile);

  String get imageSizeFormatted {
    if (imageSize < 1024) return '$imageSize B';
    if (imageSize < 1024 * 1024)
      return '${(imageSize / 1024).toStringAsFixed(0)} KB';
    return '${(imageSize / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  factory Wallpaper.fromJson(Map<String, dynamic> json) {
    return Wallpaper(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      imageFile: json['imageFile'] as String? ?? '',
      previewFile: json['previewFile'] as String? ?? '',
      imageSize: json['imageSize'] as int? ?? 0,
      previewSize: json['previewSize'] as int? ?? 0,
      glowColor: json['glowColor'] as String? ?? '#FFFFFF',
      category: json['category'] as String? ?? 'MISC',
      badge: json['badge'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
      featured: json['featured'] as bool? ?? false,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
      downloadCount: json['downloadCount'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      cultural: json['cultural'] is Map<String, dynamic>
          ? CulturalContent.fromJson(json['cultural'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Factory for Postgres `wallpapers_v` view rows (snake_case columns).
  /// Maps the new schema to the existing field names so the rest of the app
  /// doesn't need to change.
  factory Wallpaper.fromSupabase(Map<String, dynamic> row) {
    return Wallpaper(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String? ?? '',
      imageFile: row['image_path'] as String? ?? '',
      previewFile: row['preview_path'] as String? ?? '',
      imageSize: (row['image_size'] as num?)?.toInt() ?? 0,
      previewSize: (row['preview_size'] as num?)?.toInt() ?? 0,
      glowColor: row['glow_color'] as String? ?? '#FFFFFF',
      category: row['category'] as String? ?? 'MISC',
      badge: row['badge'] as String?,
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      featured: row['featured'] as bool? ?? false,
      tags:
          (row['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
      downloadCount: (row['install_count'] as num?)?.toInt() ?? 0,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'] as String)
          : null,
      cultural: row['cultural'] is Map<String, dynamic>
          ? CulturalContent.fromJson(row['cultural'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Is this wallpaper "new" (added within last 14 days)?
  bool get isNew {
    if (createdAt == null) return badge == 'NEW';
    return DateTime.now().difference(createdAt!).inDays <= 14;
  }

  /// Whether this is a panoramic wallpaper (ultra-wide).
  bool get isPanoramic => category == 'PANORAMIC';

  /// Convert to unified ContentItem for ContentManager.
  ContentItem toContentItem({bool asLive = false}) {
    final type = isPanoramic
        ? ContentType.panoramicWallpaper
        : ContentType.staticWallpaper;
    return ContentItem(
      id: id,
      type: type,
      remoteFile: imageFile,
      bucket: ContentUrlResolver.wallpaperImagesBucket,
      previewFile: previewFile,
      name: name,
      metadata: {
        'glowColor': glowColor,
        'category': category,
        'interactive': false,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'imageFile': imageFile,
        'previewFile': previewFile,
        'imageSize': imageSize,
        'previewSize': previewSize,
        'glowColor': glowColor,
        'category': category,
        'badge': badge,
        'sortOrder': sortOrder,
        'featured': featured,
        'tags': tags,
        'downloadCount': downloadCount,
        'createdAt': createdAt?.toIso8601String(),
      };
}
