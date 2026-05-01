import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/ad_service.dart';
import '../services/sprite_download_service.dart';
import '../services/wallpaper_stats_service.dart';
import 'content_cache.dart';
import 'content_downloader.dart';
import 'content_types.dart';
import 'installers/content_installer.dart';
import 'installers/static_wallpaper_installer.dart';
import 'installers/live_wallpaper_installer.dart';
import 'installers/ringtone_installer.dart';
import 'installers/story_installer.dart';
import 'installers/day_cycle_installer.dart';
import 'installers/aura_installer.dart';

/// Unified content manager for Pixora.
/// Single entry point for downloading, caching, and installing ANY content.
///
/// Usage:
/// ```dart
/// await ContentManager.instance.downloadAndInstall(
///   item: wallpaper.toContentItem(),
///   target: InstallTarget.liveWallpaper,
///   onProgress: (p) => setState(() => _progress = p),
///   onError: (msg) => showSnackbar(msg),
/// );
/// ```
class ContentManager {
  ContentManager._();
  static final instance = ContentManager._();

  final _downloader = ContentDownloader.instance;
  final _cache = ContentCache.instance;

  /// Installer registry — one per content type.
  final Map<ContentType, ContentInstaller> _installers = {
    ContentType.staticWallpaper: StaticWallpaperInstaller(),
    ContentType.panoramicWallpaper: StaticWallpaperInstaller(),
    ContentType.liveVideo: LiveWallpaperInstaller(),
    ContentType.liveVideoExplore: LiveWallpaperInstaller(),
    ContentType.ringtone: RingtoneInstaller(),
    ContentType.notification: RingtoneInstaller(),
    ContentType.alarm: RingtoneInstaller(),
    ContentType.story: StoryInstaller(),
    ContentType.dayCycle: DayCycleInstaller(),
    ContentType.auraTrack: AuraInstaller(),
  };

  // ── Download only ──────────────────────────────────────────

  /// Download content to local cache. Returns local path or null.
  Future<String?> download(
    ContentItem item, {
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
  }) {
    return _downloader.download(item, onProgress: onProgress, onError: onError);
  }

  // ── Install only (from already-cached path) ────────────────

  /// Install from a local path. Assumes content is already downloaded.
  /// The installer is resolved by INSTALL TARGET first, then by content type.
  /// This ensures a static wallpaper installed as "live wallpaper" uses the
  /// LiveWallpaperInstaller (with clock + equalizer), not StaticWallpaperInstaller.
  Future<bool> install(
    String localPath,
    ContentItem item,
    InstallTarget target,
  ) {
    final installer = _resolveInstaller(item, target);
    return installer.install(localPath, item, target);
  }

  ContentInstaller _resolveInstaller(ContentItem item, InstallTarget target) {
    // Install target overrides content-type-based installer
    switch (target) {
      case InstallTarget.liveWallpaper:
        return LiveWallpaperInstaller();
      case InstallTarget.ringtone:
      case InstallTarget.notificationSound:
      case InstallTarget.alarmSound:
        return RingtoneInstaller();
      case InstallTarget.play:
      case InstallTarget.offline:
        if (item.type == ContentType.auraTrack) return AuraInstaller();
        return _installers[item.type] ?? StaticWallpaperInstaller();
      default:
        return _installers[item.type] ?? StaticWallpaperInstaller();
    }
  }

  // ── Download + Install (most common) ───────────────────────

  /// Download content, then install it. Handles ads and diamond rewards.
  /// This is the primary method most pages should call.
  Future<bool> downloadAndInstall({
    required ContentItem item,
    required InstallTarget target,
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
    void Function(String phase)? onPhase,
    bool showAd = true,
  }) async {
    // Track the download
    WallpaperStatsService.instance.trackDownload(item.id);

    // Phase 1: Download
    onPhase?.call('downloading');
    final path = await download(item, onProgress: onProgress, onError: onError);
    if (path == null) return false;

    // Phase 2: Download sprites if animated wallpaper theme.
    // If sprite download fails we abort — installing without sprites would leave
    // the user with a silent, animation-less wallpaper and no clear feedback.
    final theme = SpriteDownloadService.instance.detectTheme(item.remoteFile);
    if (theme != null) {
      onPhase?.call('sprites');
      final spritesOk = await SpriteDownloadService.instance
          .ensureSpritesForTheme(theme, onProgress: onProgress);
      if (!spritesOk) {
        onError?.call(
            'Could not download animated sprites. Check your connection and try again.');
        return false;
      }
    }

    // Phase 3: Install
    onPhase?.call('installing');
    onProgress?.call(0.0);
    final success = await install(path, item, target);

    if (success) {
      // Track the install event AFTER native call succeeded.
      WallpaperStatsService.instance.trackInstall(item.id);
      onPhase?.call('done');
    } else {
      onError?.call('Installation failed');
    }

    return success;
  }

  /// Download + install with alternating ad (same rules as wallpapers).
  /// Shows ad on odd actions, skips on even. Awards diamonds when ad shows.
  Future<bool> downloadAndInstallWithAd({
    required ContentItem item,
    required InstallTarget target,
    required VoidCallback onComplete,
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
  }) async {
    final completer = _AdCompleter();

    AdService.instance.showInterstitialAd(
      placement: 'wallpaper_apply',
      wallpaperId: item.id,
      onAdDismissed: () async {
        final success = await downloadAndInstall(
          item: item,
          target: target,
          onProgress: onProgress,
          onError: onError,
          showAd: false,
        );
        completer.complete(success);
        onComplete();
      },
    );

    return completer.future;
  }

  // ── Cache management ───────────────────────────────────────

  /// Check if content is cached locally.
  Future<bool> isCached(ContentItem item) => _cache.isCached(item);

  /// Total cache size in bytes.
  Future<int> getCacheSize() => _cache.totalSizeBytes();

  /// Clear all cached content.
  Future<void> clearCache() => _cache.clearAll();

  /// Get local path for a cached item (may not exist).
  Future<String> getCachePath(ContentItem item) => _cache.pathFor(item);
}

/// Simple completer wrapper for ad callback flow.
class _AdCompleter {
  final _completer = Completer<bool>();
  Future<bool> get future => _completer.future;
  void complete(bool value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }
}
