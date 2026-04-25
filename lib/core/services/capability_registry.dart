/// Declares what content types + schema versions this app build can render.
/// Items in the catalog index whose (type, schema) is not listed here are
/// silently filtered out — keeps old clients safe when new types ship.
///
/// See: docs/schemas/scene_v1.md
class CapabilityRegistry {
  /// Top-level content types and the schema versions this client supports.
  /// To add a new type or schema version: ship an app update with the
  /// corresponding renderer/player wired in.
  static const Map<String, List<int>> supportedTypes = {
    'static_wallpaper': [1],
    'panoramic_wallpaper': [1],
    'video_wallpaper': [1],
    'canvas_scene': [1],
    'shader_scene': [1],
    'day_cycle': [1],
    'story': [1],
    'ringtone': [1],
    'aura_track': [1],
  };

  /// canvas_scene vocabulary — sprite movement patterns the renderer knows.
  static const Set<String> knownSpriteBehaviors = {
    'orbit',
    'wander',
    'translate',
    'static',
    'preload',
  };

  /// canvas_scene vocabulary — particle systems the renderer knows.
  static const Set<String> knownParticles = {
    'embers',
    'motes',
    'bubbles',
    'snow',
    'rain',
    'wisps',
  };

  /// canvas_scene vocabulary — cinematic events the renderer knows.
  static const Set<String> knownEvents = {
    'phoenix',
    'lightning_procedural',
    'lightning_sprite',
    'bat_swarm',
    'flash_overlay',
  };

  /// shader_scene vocabulary — uniform GLSL types the engine can bind.
  static const Set<String> knownUniformTypes = {
    'float',
    'int',
    'vec2',
    'vec3',
    'vec4',
    'mat4',
  };

  /// Returns true if the catalog index entry can be rendered. Use this to
  /// drop items from result lists silently.
  static bool itemSupported(Map<String, dynamic> indexEntry) {
    final type = indexEntry['type'] as String?;
    final schema = indexEntry['schema'] as int?;
    if (type == null || schema == null) return false;
    final supportedSchemas = supportedTypes[type];
    if (supportedSchemas == null) return false;
    return supportedSchemas.contains(schema);
  }

  /// Validates a fully-loaded scene spec. If any nested vocabulary is
  /// unknown, the whole spec is rejected — better to hide than render
  /// half-broken.
  static bool sceneSpecValid(Map<String, dynamic> spec) {
    final sprites = (spec['sprites'] as List?) ?? const [];
    for (final s in sprites) {
      final b = (s as Map)['behavior'] as String?;
      if (b == null || !knownSpriteBehaviors.contains(b)) return false;
    }
    final particles = (spec['particles'] as List?) ?? const [];
    for (final p in particles) {
      final k = (p as Map)['kind'] as String?;
      if (k == null || !knownParticles.contains(k)) return false;
    }
    final events = (spec['events'] as List?) ?? const [];
    for (final e in events) {
      final k = (e as Map)['kind'] as String?;
      if (k == null || !knownEvents.contains(k)) return false;
    }
    final uniforms = (spec['uniforms'] as Map?) ?? const {};
    for (final u in uniforms.values) {
      final t = (u as Map)['type'] as String?;
      if (t == null || !knownUniformTypes.contains(t)) return false;
    }
    return true;
  }

  /// Convenience: filter a list of catalog index entries down to only
  /// items this app build can render.
  static List<Map<String, dynamic>> filterIndex(
    List<Map<String, dynamic>> items,
  ) =>
      items.where(itemSupported).toList(growable: false);
}
