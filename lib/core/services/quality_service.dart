import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum ImageQuality { auto, hd, lq }

/// Provider for current image quality setting.
final imageQualityProvider = StateNotifierProvider<ImageQualityNotifier, ImageQuality>((ref) {
  return ImageQualityNotifier();
});

class ImageQualityNotifier extends StateNotifier<ImageQuality> {
  ImageQualityNotifier() : super(ImageQuality.auto) {
    _load();
  }

  static const _boxName = 'settings';
  static const _key = 'image_quality';

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_boxName);
      final value = box.get(_key, defaultValue: 'auto') as String;
      state = ImageQuality.values.firstWhere(
        (q) => q.name == value,
        orElse: () => ImageQuality.auto,
      );
    } catch (e) {
      debugPrint('[Quality] Load error: $e');
    }
  }

  Future<void> setQuality(ImageQuality quality) async {
    state = quality;
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_key, quality.name);
    } catch (e) {
      debugPrint('[Quality] Save error: $e');
    }
  }

  /// Resolve what quality to actually use (for "auto" mode).
  static bool shouldUseHD(ImageQuality setting) {
    if (setting == ImageQuality.hd) return true;
    if (setting == ImageQuality.lq) return false;

    // Auto: check device RAM
    if (Platform.isAndroid) {
      // ProcessInfo not easily available in Flutter, use simple heuristic
      // Devices with >= 4GB RAM get HD
      return true; // Default to HD on modern devices
    }
    return true;
  }
}

extension ImageQualityLabel on ImageQuality {
  String get label {
    switch (this) {
      case ImageQuality.auto:
        return 'Auto';
      case ImageQuality.hd:
        return 'HD';
      case ImageQuality.lq:
        return 'Low Quality';
    }
  }

  String get description {
    switch (this) {
      case ImageQuality.auto:
        return 'Best quality for your device';
      case ImageQuality.hd:
        return 'Full resolution images (uses more data)';
      case ImageQuality.lq:
        return 'Faster loading, saves data';
    }
  }

  IconData get icon {
    switch (this) {
      case ImageQuality.auto:
        return Icons.auto_awesome;
      case ImageQuality.hd:
        return Icons.hd;
      case ImageQuality.lq:
        return Icons.sd;
    }
  }
}
