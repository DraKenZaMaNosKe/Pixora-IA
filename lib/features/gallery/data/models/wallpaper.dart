class Wallpaper {
  const Wallpaper({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.assetType,
    required this.sourceUrl,
    required this.tags,
    required this.durationSeconds,
    this.isPremium = false,
  });

  final String id;
  final String title;
  final String previewUrl; // thumbnail/gif
  final WallpaperAssetType assetType;
  final String sourceUrl; // video/lottie url
  final List<String> tags;
  final int durationSeconds;
  final bool isPremium;

  factory Wallpaper.fromJson(Map<String, dynamic> json) {
    return Wallpaper(
      id: json['id'] as String,
      title: json['title'] as String,
      previewUrl: json['preview_url'] as String,
      assetType: WallpaperAssetType.values.firstWhere(
        (value) => value.name == (json['asset_type'] as String? ?? 'video'),
        orElse: () => WallpaperAssetType.video,
      ),
      sourceUrl: json['source_url'] as String,
      tags: List<String>.from(json['tags'] as List? ?? []),
      durationSeconds: json['duration_seconds'] as int? ?? 10,
      isPremium: json['is_premium'] as bool? ?? false,
    );
  }
}

enum WallpaperAssetType { video, lottie }
