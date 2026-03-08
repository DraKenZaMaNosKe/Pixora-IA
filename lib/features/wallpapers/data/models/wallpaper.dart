import '../../../../core/constants/supabase_config.dart';

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

  String get previewUrl => SupabaseConfig.imageUrl(previewFile);
  String get fullImageUrl => SupabaseConfig.imageUrl(imageFile);
  String get imageSizeFormatted {
    if (imageSize < 1024) return '$imageSize B';
    if (imageSize < 1024 * 1024) return '${(imageSize / 1024).toStringAsFixed(0)} KB';
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
      };
}
