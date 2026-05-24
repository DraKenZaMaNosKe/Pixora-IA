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
    this.dailyEligible = false,
    this.tags = const [],
    this.downloadCount = 0,
    this.createdAt,
    this.cultural,
    this.authorName = 'Pixora Studio',
    this.authorUserId,
    this.customPreviewUrl,
    this.mediaWidth,
    this.mediaHeight,
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
  // True si el admin marcó este wallpaper como eligible para rotar en
  // Pixora Daily (curado). Independiente de category — un wallpaper puede
  // estar en ANIME y a la vez ser daily_eligible. Solo en STATIC wallpapers
  // (la tabla Postgres tiene la columna).
  final bool dailyEligible;
  final List<String> tags;
  final int downloadCount;
  final DateTime? createdAt;

  /// Optional editorial content for cultural / mythology wallpapers — when
  /// non-null, the detail page renders the Códice layout instead of the
  /// plain description view. Lives in the catalog so new entries ship
  /// without rebuilding the APK.
  final CulturalContent? cultural;

  /// Display name of the author. Default 'Pixora Studio' for catalog wallpapers
  /// uploaded by the team. Set to the user's display name for user-published
  /// wallpapers (Phase 2 feature).
  final String authorName;

  /// Optional FK to a future profiles table for user-published wallpapers.
  /// When non-null, tapping the author opens their profile / gallery.
  /// Always null for catalog wallpapers uploaded by the Pixora team.
  final int? authorUserId;

  /// Optional override for the preview URL. When non-null, used INSTEAD of
  /// `SupabaseConfig.imageUrl(previewFile)`. Useful for adapter cases where
  /// the file lives in a different bucket (e.g. LiveWallpaper previews live
  /// in the `wallpaper-videos` bucket, not `wallpaper-images`).
  final String? customPreviewUrl;

  /// Pixel dimensions of the source media. Null for legacy items pending
  /// backfill. Filled by the upload pipeline (or the backfill script that
  /// downloads + measures with Pillow). Used by the dimension-agnostic UI
  /// (Fase 2) to decide rendering: ultra-wide → horizontal scroll,
  /// vertical → fullscreen, etc.
  final int? mediaWidth;
  final int? mediaHeight;

  /// Aspect ratio (width / height). Null if dimensions are unknown. Use
  /// `aspectRatio ?? <fallback>` if you need a non-null value (most callers
  /// can default to the legacy assumption of 9:16 = 0.5625 for static or
  /// 4:1 = 4.0 for panoramic, based on `isPanoramic`).
  double? get aspectRatio {
    if (mediaWidth == null || mediaHeight == null || mediaHeight! <= 0) {
      return null;
    }
    return mediaWidth! / mediaHeight!;
  }

  String get previewUrl =>
      customPreviewUrl ?? SupabaseConfig.imageUrl(previewFile);
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
      dailyEligible: json['dailyEligible'] as bool? ?? false,
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
      authorName: json['authorName'] as String? ?? 'Pixora Studio',
      authorUserId: json['authorUserId'] as int?,
      mediaWidth: (json['mediaWidth'] as num?)?.toInt(),
      mediaHeight: (json['mediaHeight'] as num?)?.toInt(),
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
      dailyEligible: row['daily_eligible'] as bool? ?? false,
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
      authorName: row['author_name'] as String? ?? 'Pixora Studio',
      authorUserId: (row['author_user_id'] as num?)?.toInt(),
      mediaWidth: (row['media_width'] as num?)?.toInt(),
      mediaHeight: (row['media_height'] as num?)?.toInt(),
    );
  }

  /// Is this wallpaper "new" (added within last 14 days)?
  bool get isNew {
    if (createdAt == null) return badge == 'NEW';
    return DateTime.now().difference(createdAt!).inDays <= 14;
  }

  /// Whether this wallpaper should be treated as panoramic (ultra-wide).
  ///
  /// Hybrid detection — Fase 2 of the dimension-agnostic refactor:
  ///   1. If `aspectRatio >= 3.0` → panoramic (detected from real dimensions,
  ///      so any wallpaper with ultra-wide source qualifies regardless of
  ///      which thematic category it lives in).
  ///   2. Else if `category == 'PANORAMIC'` → panoramic (legacy/manual tag,
  ///      preserves behavior for items pending dimension backfill or items
  ///      explicitly curated as panoramic).
  ///
  /// Defense in depth: either signal triggers panoramic rendering, so we
  /// never accidentally hide an item during the transition.
  bool get isPanoramic {
    final ratio = aspectRatio;
    if (ratio != null && ratio >= 3.0) return true;
    return category == 'PANORAMIC';
  }

  /// Convert to unified ContentItem for ContentManager.
  ///
  /// When [asLive] is true, the wallpaper is treated as a LIVE video item:
  /// the file lives in the `wallpaper-videos` bucket and the type maps to
  /// `liveVideo` so `ContentManager.downloadAndInstall` resolves the right
  /// URL and installs via the live-wallpaper pipeline. The adapter
  /// `wallpaperFromLive()` stores the video path in `imageFile` precisely
  /// for this case (with `customPreviewUrl` already pointing to the right
  /// preview bucket).
  ContentItem toContentItem({bool asLive = false}) {
    if (asLive) {
      return ContentItem(
        id: id,
        type: ContentType.liveVideo,
        remoteFile: imageFile,
        bucket: ContentUrlResolver.wallpaperVideosBucket,
        previewFile: previewFile,
        name: name,
        metadata: {
          'glowColor': glowColor,
          'category': category,
          'interactive': false,
        },
      );
    }
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
        'authorName': authorName,
        'authorUserId': authorUserId,
      };
}
