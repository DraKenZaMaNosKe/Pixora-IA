import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/supabase_config.dart';
import 'catalog_cache_store.dart';
import 'download_service.dart';
import '../../features/ringtones/data/models/ringtone_pack.dart';

class RingtoneService {
  RingtoneService._();
  static final instance = RingtoneService._();

  static const _channel = MethodChannel('com.orbix.pixora/wallpaper');
  static const _catalogFile = 'ringtones_catalog.json';
  static const _cacheKey = 'images:ringtones_catalog.json';
  static const _ttl = Duration(hours: 6);

  List<RingtonePack> _packs = [];
  DateTime? _lastFetch;

  Future<void> clearCache() async {
    _packs = [];
    _lastFetch = null;
    await CatalogCacheStore.instance.clear(_cacheKey);
  }

  Future<List<RingtonePack>> fetchCatalog({bool forceRefresh = false}) async {
    if (_packs.isNotEmpty &&
        !forceRefresh &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _ttl) {
      return _packs;
    }
    final url =
        '${SupabaseConfig.storageBase}/${SupabaseConfig.imagesBucket}/$_catalogFile';
    final result = await CatalogCacheStore.instance.fetchWithCache(
      key: _cacheKey,
      url: url,
      ttl: _ttl,
      forceRefresh: forceRefresh,
    );
    if (result.hasBody) {
      try {
        final data = jsonDecode(result.body!) as Map<String, dynamic>;
        final list = (data['packs'] as List<dynamic>?) ?? [];
        _packs = list
            .map((e) => RingtonePack.fromJson(e as Map<String, dynamic>))
            .toList();
        _lastFetch = DateTime.now();
        debugPrint(
            '[Pixora] Ringtone catalog loaded (${result.source.name}): ${_packs.length}');
      } catch (e) {
        debugPrint('[Pixora] Ringtone parse error: $e');
      }
    }
    return _packs;
  }

  /// Download a ringtone file and return the local path.
  /// Uses DownloadService for retry, connectivity check, and validation.
  Future<String?> downloadTone(
    RingtoneTone tone, {
    void Function(String message)? onError,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/ringtones/${tone.id}.mp3');

      return await DownloadService.instance.downloadFile(
        tone.fileUrl,
        file,
        retries: 3,
        timeoutSeconds: 60,
        minBytes: 500, // MP3 files should be at least 500 bytes
        onError: onError,
      );
    } catch (e) {
      debugPrint('[Pixora] Ringtone download failed: $e');
      onError?.call('Download failed');
      return null;
    }
  }

  /// Check if the app has WRITE_SETTINGS permission.
  Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final result =
          await _channel.invokeMethod<bool>('checkWriteSettingsPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('[Pixora] Check permission failed: $e');
      return false;
    }
  }

  /// Open system settings to grant WRITE_SETTINGS permission.
  Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestWriteSettingsPermission');
    } catch (e) {
      debugPrint('[Pixora] Request permission failed: $e');
    }
  }

  /// Set a downloaded ringtone as the system ringtone/notification/alarm.
  /// type: 0 = ringtone, 1 = notification, 2 = alarm
  Future<bool> setAsRingtone(String filePath, String title, int type) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('setRingtone', {
        'path': filePath,
        'title': title,
        'type': type,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[Pixora] Set ringtone failed: $e');
      return false;
    }
  }
}
