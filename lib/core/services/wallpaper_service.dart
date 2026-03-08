import 'dart:io';
import 'package:flutter/services.dart';

class WallpaperService {
  WallpaperService._();
  static final instance = WallpaperService._();

  static const _channel = MethodChannel('com.orbix.pixora/wallpaper');

  /// Set wallpaper on Android. [target]: 0=home, 1=lock, 2=both
  Future<bool> setWallpaper(String filePath, int target) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'setWallpaper',
        {'path': filePath, 'target': target},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Save image to gallery (iOS flow)
  Future<bool> saveToGallery(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'saveToGallery',
        {'path': filePath},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
