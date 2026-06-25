import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Tracks wallpaper IDs that should NEVER appear como Mystery cards.
///
/// Reasons a wallpaper gets excluded:
///   - User installed it (applied as wallpaper). No point of mystery after.
///   - User explicitly hid the mystery for it (future feature).
///
/// Favorites are checked separately via Hive box 'favorites' — no need
/// to duplicate state.
///
/// Storage: Hive box `mystery_excluded` (Set<String> via key-value).
/// Sync: local-only (per-device). If user changes devices their mystery
/// pool resets, which is intentional — fresh device = fresh discovery.
class MysteryExclusionService {
  MysteryExclusionService._();
  static final instance = MysteryExclusionService._();

  static const _boxName = 'mystery_excluded';
  Box<bool>? _box;
  bool _initialized = false;

  /// Initialize the Hive box. Safe to call multiple times.
  /// Defensive: any error logs but doesn't throw — Mystery system
  /// should never break the app even if Hive is misbehaving.
  Future<void> init() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox<bool>(_boxName);
      _initialized = true;
      debugPrint(
        '[MysteryExclusion] init: ${_box?.length ?? 0} IDs excluded',
      );
    } catch (e) {
      debugPrint('[MysteryExclusion] init failed: $e');
    }
  }

  /// Mark a wallpaper as excluded (e.g. user just installed it).
  /// Fire-and-forget — non-critical.
  Future<void> exclude(String wallpaperId) async {
    try {
      if (_box == null) await init();
      await _box?.put(wallpaperId, true);
    } catch (e) {
      debugPrint('[MysteryExclusion] exclude failed: $e');
    }
  }

  /// Synchronous check. Returns false if box not initialized yet
  /// (safe default — better to show mystery than break).
  bool isExcluded(String wallpaperId) {
    try {
      return _box?.get(wallpaperId) == true;
    } catch (_) {
      return false;
    }
  }
}
