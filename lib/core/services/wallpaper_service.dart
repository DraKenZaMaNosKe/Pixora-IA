import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Servicio para aplicar wallpapers (Android) o guardar en galería (iOS).
///
/// Android: usa MethodChannel → WallpaperManager nativo (Kotlin).
/// iOS:     no tiene WallpaperManager — retorna false con log claro.
///          El flujo iOS se maneja en WallpaperPreviewPage via Share sheet.
class WallpaperService {
  WallpaperService._();
  static final instance = WallpaperService._();

  static const _channel = MethodChannel('com.orbix.pixora/wallpaper');

  /// Establece el wallpaper en Android.
  /// [target]: 0 = Home, 1 = Lock, 2 = Ambos.
  /// Retorna false en iOS (no soportado vía WallpaperManager).
  Future<bool> setWallpaper(String filePath, int target) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'setWallpaper',
        {'path': filePath, 'target': target},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[WallpaperService] setWallpaper error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[WallpaperService] setWallpaper unexpected error: $e');
      return false;
    }
  }

  /// Guarda imagen en galería del dispositivo.
  /// Android: usa MediaStore via MethodChannel (Kotlin).
  /// iOS:     usa PHPhotoLibrary via MethodChannel (Swift).
  ///
  /// Returns true on success. On failure, throws or returns false.
  /// [lastError] contains details if the native side reported an error.
  String? lastError;

  Future<bool> saveToGallery(String filePath) async {
    lastError = null;
    try {
      debugPrint('[WallpaperService] saveToGallery path: $filePath');
      final result = await _channel.invokeMethod<bool>(
        'saveToGallery',
        {'path': filePath},
      );
      debugPrint('[WallpaperService] saveToGallery result: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      lastError = '${e.code}: ${e.message}';
      debugPrint(
          '[WallpaperService] saveToGallery PlatformException: $lastError');
      return false;
    } catch (e) {
      lastError = e.toString();
      debugPrint('[WallpaperService] saveToGallery unexpected: $lastError');
      return false;
    }
  }

  /// Activa el Live Wallpaper con efecto touch glow.
  /// Abre el selector de Android para confirmar.
  ///
  /// [sceneId] — when set, activates the data-driven CanvasSceneRenderer
  /// using a spec previously cached at filesDir/scene_specs/<id>.json
  /// by SceneSpecService. The Kotlin side reads it on engine boot.
  Future<bool> setLiveWallpaper(String filePath, String glowColor,
      {bool interactive = false, String? sceneId}) async {
    if (!Platform.isAndroid) return false;
    // TEMP v1.7 bring-up: auto-detect known canvas_scene wallpapers from
    // path so we can validate the data-driven renderer end-to-end before
    // wiring the catalog index. Remove once index is live.
    var resolvedScene = sceneId;
    if (resolvedScene == null) {
      for (final candidate in _knownCanvasScenes.keys) {
        if (filePath.contains(candidate)) {
          resolvedScene = candidate;
          await _ensureSceneSpecCached(candidate);
          break;
        }
      }
    }
    try {
      final args = <String, Object?>{
        'path': filePath,
        'glowColor': glowColor,
        'interactive': interactive,
      };
      if (resolvedScene != null && resolvedScene.isNotEmpty) {
        args['sceneId'] = resolvedScene;
      }
      final result =
          await _channel.invokeMethod<bool>('setLiveWallpaper', args);
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[WallpaperService] setLiveWallpaper error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[WallpaperService] setLiveWallpaper unexpected error: $e');
      return false;
    }
  }

  // TEMP v1.7 bring-up — id → public spec URL. Replace with catalog index.
  static const _knownCanvasScenes = <String, String>{
    'volcano_dragon':
        'https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public/wallpaper-scenes/volcano_dragon.json',
    'dusk_fortress':
        'https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public/wallpaper-scenes/dusk_fortress.json',
    'bosque_lluvioso':
        'https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public/wallpaper-scenes/bosque_lluvioso.json',
  };

  Future<void> _ensureSceneSpecCached(String sceneId) async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/scene_specs');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$sceneId.json');
      if (file.existsSync() && file.lengthSync() > 100) return; // cached
      final url = _knownCanvasScenes[sceneId]!;
      final r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && r.bodyBytes.length > 100) {
        await file.writeAsBytes(r.bodyBytes);
        debugPrint('[WallpaperService] cached scene spec: $sceneId '
            '(${r.bodyBytes.length} B)');
      } else {
        debugPrint('[WallpaperService] scene spec fetch HTTP ${r.statusCode}');
      }
    } catch (e) {
      debugPrint('[WallpaperService] scene spec fetch error: $e');
    }
  }

  /// Reset the live wallpaper engine — releases all codecs, bitmaps, players.
  Future<bool> resetEngine() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('resetEngine');
      return result ?? false;
    } catch (e) {
      debugPrint('[WallpaperService] resetEngine error: $e');
      return false;
    }
  }

  /// Read the current overlay visibility flags from native prefs.
  /// Keys: clock, battery, ram, storage, equalizer. Missing entries default true.
  Future<Map<String, bool>> getOverlayVisibility() async {
    if (!Platform.isAndroid) {
      return const {
        'clock': true,
        'battery': true,
        'ram': true,
        'storage': true,
        'equalizer': true,
      };
    }
    try {
      final result = await _channel.invokeMethod<Map>('getOverlayVisibility');
      if (result == null) return const {};
      return result.map((k, v) => MapEntry(k.toString(), v == true));
    } catch (e) {
      debugPrint('[WallpaperService] getOverlayVisibility error: $e');
      return const {};
    }
  }

  /// Toggle a single overlay. Writes to prefs and broadcasts to the :wallpaper
  /// process so the change is reflected immediately, no app restart needed.
  Future<bool> setOverlayVisibility(String key, bool value) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'setOverlayVisibility',
        {'key': key, 'value': value},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[WallpaperService] setOverlayVisibility error: $e');
      return false;
    }
  }
}
