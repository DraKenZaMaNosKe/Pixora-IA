import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
      debugPrint('[WallpaperService] saveToGallery PlatformException: $lastError');
      return false;
    } catch (e) {
      lastError = e.toString();
      debugPrint('[WallpaperService] saveToGallery unexpected: $lastError');
      return false;
    }
  }

  /// Activa el Live Wallpaper con efecto touch glow.
  /// Abre el selector de Android para confirmar.
  Future<bool> setLiveWallpaper(String filePath, String glowColor) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'setLiveWallpaper',
        {'path': filePath, 'glowColor': glowColor},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[WallpaperService] setLiveWallpaper error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[WallpaperService] setLiveWallpaper unexpected error: $e');
      return false;
    }
  }
}
