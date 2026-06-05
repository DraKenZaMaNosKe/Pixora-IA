import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'catalog_index_service.dart';
import 'scene_spec_service.dart';

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
  /// [sceneId] — caller can pre-resolve the canvas_scene id. Otherwise this
  /// method derives it from the wallpaper filename by looking up the
  /// catalog index — if the matching entry is a `canvas_scene`, the spec
  /// is cached to filesDir and `sceneId` is passed to the native engine.
  Future<bool> setLiveWallpaper(String filePath, String glowColor,
      {bool interactive = false, String? sceneId}) async {
    if (!Platform.isAndroid) return false;
    final resolvedScene =
        sceneId ?? await _resolveCanvasSceneFromPath(filePath);
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

  /// Public wrapper around the catalog_index lookup. Used by installers
  /// (e.g. StaticWallpaperInstaller) to upgrade a static IMAGE apply into
  /// a live canvas_scene apply when the basename matches a canvas_scene.
  Future<String?> resolveCanvasSceneFromPath(String filePath) =>
      _resolveCanvasSceneFromPath(filePath);

  /// Look up the wallpaper filename in the catalog index. If it's a
  /// canvas_scene, fetch the spec to filesDir and return the scene id
  /// (so the native engine activates CanvasSceneRenderer).
  ///
  /// Tries the basename as-is AND with the "pixora_" prefix stripped
  /// (because dynamic_catalog ids are prefixed but scene specs aren't).
  Future<String?> _resolveCanvasSceneFromPath(String filePath) async {
    try {
      // Extract basename without extension
      final fname = filePath.split(RegExp(r'[\\/]')).last;
      final basename = fname.contains('.')
          ? fname.substring(0, fname.lastIndexOf('.'))
          : fname;
      final candidates = <String>{
        basename,
        if (basename.startsWith('pixora_')) basename.substring(7),
      };
      for (final id in candidates) {
        final entry = await CatalogIndexService.instance.findById(id);
        if (entry != null && entry.type == 'canvas_scene') {
          // Cache the spec to filesDir so native side can read it
          await SceneSpecService.instance.fetch(entry);
          return id;
        }
      }
    } catch (e) {
      debugPrint('[WallpaperService] resolveCanvasScene error: $e');
    }
    return null;
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

  // ── Touch trail picker ────────────────────────────────────────────

  /// All available touch trail style ids, in display order.
  static const List<String> touchTrailIds = [
    'aurora',
    'sparks',
    'comet',
    'lightning',
    'petals',
    'stardust',
    'pixora_gold',
  ];

  /// Read the user's current touch trail style ('aurora' if never set).
  Future<String> getTouchTrail() async {
    if (!Platform.isAndroid) return 'aurora';
    try {
      final r = await _channel.invokeMethod<String>('getTouchTrail');
      return r ?? 'aurora';
    } catch (e) {
      debugPrint('[WallpaperService] getTouchTrail error: $e');
      return 'aurora';
    }
  }

  /// Set the touch trail style. Broadcasts to :wallpaper so the change
  /// applies instantly without requiring an app restart.
  Future<bool> setTouchTrail(String style) async {
    if (!Platform.isAndroid) return false;
    try {
      final r =
          await _channel.invokeMethod<bool>('setTouchTrail', {'style': style});
      return r ?? false;
    } catch (e) {
      debugPrint('[WallpaperService] setTouchTrail error: $e');
      return false;
    }
  }

  /// All 10 selectable HUD presets, keyed by native [HudPreset.key] enum value.
  /// Order matters — this is the order shown in the Settings picker.
  static const List<({String key, String name, String sub})> hudPresets = [
    (key: 'sacred', name: 'Pixora Sacred', sub: 'Brand · dorado cósmico'),
    (key: 'modern', name: 'Modern Mono', sub: 'iOS · Winamp mirror'),
    (key: 'gemini', name: 'Gemini Pulse', sub: 'Google AI · dots'),
    (key: 'grok', name: 'Grok Spectrum', sub: 'Bars vivos multi-color'),
    (key: 'crt', name: 'CRT Terminal', sub: 'Sci-fi cyan · scanlines'),
    (key: 'retro', name: 'Retro CRT', sub: 'VT323 verde · hacker'),
    (key: 'flame', name: 'Flame Wisps', sub: 'Llamas · primal'),
    (key: 'aurora', name: 'Aurora Boreal', sub: 'Cintas · cielo estrellado'),
    (key: 'cyber', name: 'Cyber Glitch', sub: 'Amarillo · RGB split'),
    (key: 'crystal', name: 'Light Crystal', sub: 'Theme claro · prisma'),
  ];

  /// Read the user's current HUD preset ('classic' default).
  Future<String> getHudPreset() async {
    if (!Platform.isAndroid) return 'classic';
    try {
      final r = await _channel.invokeMethod<String>('getHudPreset');
      return r ?? 'classic';
    } catch (e) {
      debugPrint('[WallpaperService] getHudPreset error: $e');
      return 'classic';
    }
  }

  /// Set the HUD preset and broadcast to :wallpaper for instant reload.
  Future<bool> setHudPreset(String preset) async {
    if (!Platform.isAndroid) return false;
    try {
      final r =
          await _channel.invokeMethod<bool>('setHudPreset', {'preset': preset});
      return r ?? false;
    } catch (e) {
      debugPrint('[WallpaperService] setHudPreset error: $e');
      return false;
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
