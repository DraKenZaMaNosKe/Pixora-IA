import '../../../core/constants/supabase_config.dart';

/// A REALM shader wallpaper — fragment shader rendered by
/// `ShaderWallpaperService` in real time. Distinct from `LiveWallpaper`
/// (MP4-backed videos): no videoFile, no expectedSize comparison; apply
/// path is `MethodChannel('com.orbix.pixora/wallpaper').setShaderWallpaper`.
enum RealmCategory {
  /// Abstract / decorative shader (universe, plasma_orbs, etc.).
  abstract_,

  /// Functional clock that reads `uClockSec` from wall-clock time.
  clock,
}

class RealmShader {
  /// Shader name (matches the .glsl filename without extension, and the
  /// SharedPreferences value the engine reads via `loadCurrentShader`).
  final String id;
  final String name;
  final String description;
  final RealmCategory category;

  /// Accent color used by the card border/glow — matches the shader's
  /// dominant palette.
  final String glowColor;

  /// Preview WebP key inside the `wallpaper-images` bucket. Uploaded by
  /// `tools/wallpapers/upload_realm_previews.py` (or inline build step).
  final String previewKey;

  /// Optional badge text rendered on the card (NEW, HOT, etc.). Auto-expires
  /// follow the same convention as `LiveWallpaper.effectiveBadge`.
  final String? badge;

  const RealmShader({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.glowColor,
    required this.previewKey,
    this.badge,
  });

  String get previewUrl =>
      '${SupabaseConfig.storageBase}/wallpaper-images/$previewKey';

  /// Parse a single shader from the Supabase Storage JSON (see
  /// `tools/shaders/generate_catalog.py`). Tolerant to missing fields:
  /// returns null when required keys are absent rather than throwing,
  /// so a single broken entry doesn't kill the whole catalog load.
  static RealmShader? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final name = j['name'] as String?;
    final desc = j['description'] as String? ?? '';
    final cat = j['category'] as String?;
    final glow = j['glowColor'] as String? ?? '#E6B655';
    final preview = j['previewKey'] as String?;
    if (id == null || name == null || cat == null || preview == null)
      return null;
    return RealmShader(
      id: id,
      name: name,
      description: desc,
      category: cat == 'clock' ? RealmCategory.clock : RealmCategory.abstract_,
      glowColor: glow,
      previewKey: preview,
      badge: j['badge'] as String?,
    );
  }
}
