import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../design/hud_tokens.dart';

/// Manages the active Pixora visual theme.
///
/// Three presets supported (per
/// docs/superpowers/specs/2026-04-26-ios-theme-architecture-design.md):
///   - 'night'    → HudTheme.night    (Black & Gold — default)
///   - 'day'      → HudTheme.day      (cream day mode)
///   - 'iosWhite' → HudTheme.iosWhite (Apple Store Fresh)
///
/// Singleton ChangeNotifier per CLAUDE.md pattern. UI listens via
/// ListenableBuilder at the MaterialApp root; switching propagates everywhere
/// reading context.hud.*.
class ThemeService extends ChangeNotifier {
  ThemeService._();
  static final instance = ThemeService._();

  static const _boxName = 'pixora_theme';
  static const _key = 'active';
  static const _defaultId = 'night';

  String _activeId = _defaultId;
  Box<String>? _box;

  /// The active theme id ('night' | 'day' | 'iosWhite').
  String get activeId => _activeId;

  /// The corresponding HudTheme instance for the active id.
  HudTheme get currentTheme {
    switch (_activeId) {
      case 'iosWhite':
        return HudTheme.iosWhite;
      case 'day':
        return HudTheme.day;
      case 'night':
      default:
        return HudTheme.night;
    }
  }

  /// Open the Hive box and read the persisted choice. Call once from main()
  /// before runApp so the first frame paints with the right theme.
  Future<void> init() async {
    try {
      _box = await Hive.openBox<String>(_boxName);
      final stored = _box?.get(_key);
      if (stored != null && _isValidId(stored)) {
        _activeId = stored;
      }
    } catch (e) {
      debugPrint('[ThemeService] init failed (using default night): $e');
    }
  }

  /// Switch to a new theme. Persists immediately and notifies listeners so the
  /// UI rebuilds with the new HudTheme. Pass one of: 'night', 'day', 'iosWhite'.
  Future<void> setTheme(String id) async {
    if (!_isValidId(id)) {
      debugPrint('[ThemeService] ignoring unknown theme id "$id"');
      return;
    }
    if (_activeId == id) return;
    _activeId = id;
    try {
      await _box?.put(_key, id);
    } catch (e) {
      debugPrint('[ThemeService] persist failed: $e');
    }
    notifyListeners();
  }

  bool _isValidId(String id) =>
      id == 'night' || id == 'day' || id == 'iosWhite';

  /// Human-readable label for the active id (used in Settings).
  static String labelFor(String id) {
    switch (id) {
      case 'iosWhite':
        return 'iOS White';
      case 'day':
        return 'Cream Day';
      case 'night':
      default:
        return 'Black & Gold';
    }
  }

  /// Short tagline shown under each option in Settings.
  static String taglineFor(String id) {
    switch (id) {
      case 'iosWhite':
        return 'Apple Store · blanco · system blue';
      case 'day':
        return 'Cremoso · día · gold suave';
      case 'night':
      default:
        return 'Default · negro profundo · gold';
    }
  }

  /// All theme ids in display order (Settings UI uses this).
  static const List<String> allIds = ['night', 'day', 'iosWhite'];
}
