import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/ad_service.dart';
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
  Future<bool> install(
    String localPath,
    ContentItem item,
    InstallTarget target,
  ) {
    final installer = _installers[item.type];
    if (installer == null) {
      debugPrint('[ContentManager] No installer for ${item.type}');
      return Future.value(false);
    }
    return installer.install(localPath, item, target);
  }

  // ── Download + Install (most common) ───────────────────────

  /// Download content, then install it. Handles ads and diamond rewards.
  /// This is the primary method most pages should call.
  Future<bool> downloadAndInstall({
    required ContentItem item,
    required InstallTarget target,
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
    bool showAd = true,
  }) async {
    // Track the download
    WallpaperStatsService.instance.trackDownload(item.id);

    // Download
    final path = await download(item, onProgress: onProgress, onError: onError);
    if (path == null) return false;

    // Install
    final success = await install(path, item, target);

    if (!success) {
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
