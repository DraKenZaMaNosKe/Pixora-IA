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
}
