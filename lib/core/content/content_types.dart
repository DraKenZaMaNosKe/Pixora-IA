// Content types and unified content item model for Pixora.
// Every piece of downloadable/installable content maps to a ContentItem.

enum ContentType {
  staticWallpaper,
  panoramicWallpaper,
  liveVideo,
  liveVideoExplore,
  ringtone,
  notification,
  alarm,
  story,
  dayCycle,
  auraTrack,
}

enum InstallTarget {
  homeScreen,
  lockScreen,
  bothScreens,
  liveWallpaper,
  ringtone,
  notificationSound,
  alarmSound,
  play,
  offline,
}

/// Unified content item — wraps any downloadable/installable content in Pixora.
class ContentItem {
  final String id;
  final ContentType type;
  final String remoteFile;
  final String bucket;
  final String? previewFile;
  final String? name;
  final Map<String, dynamic> metadata;

  const ContentItem({
    required this.id,
    required this.type,
    required this.remoteFile,
    required this.bucket,
    this.previewFile,
    this.name,
    this.metadata = const {},
  });

  /// Convenience: get a metadata value with type safety.
  T? meta<T>(String key) => metadata[key] as T?;

  String get glowColor => meta<String>('glowColor') ?? '#7C4DFF';
  bool get interactive => meta<bool>('interactive') ?? false;
  int get frameCount => meta<int>('frameCount') ?? 0;
  String? get framesPath => meta<String>('framesPath');
  String? get exploreFile => meta<String>('exploreFile');
}
