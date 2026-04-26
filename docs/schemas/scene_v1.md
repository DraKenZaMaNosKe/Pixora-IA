# Pixora Scene Schema v1

The canonical contract for content delivered to the Pixora app via the
Universal Catalog Index. Goal: **add new content (wallpapers, scenes,
shaders, ringtones) without recompiling the app.**

---

## Two-tier delivery

```
Supabase Storage
├── wallpaper-images/
│   └── catalog_index.json          ← Tier 1: ALL items (light, ~200 B/item)
├── wallpaper-scenes/               ← Tier 2: per-item full spec (lazy)
│   ├── volcano_dragon.json
│   ├── cherry_blossom.json
│   └── …
├── wallpaper-shaders/              ← .glsl fragment shaders
├── wallpaper-sprites/              ← sprite ZIPs
└── wallpaper-images/               ← background WebPs, previews
```

App boot:
1. Fetch `catalog_index.json` (cached 6h)
2. Filter by capability registry (drop unknown types)
3. Render lists from index alone — never download specs for items the
   user doesn't tap

When user taps an item:
1. `SceneSpecService.fetch(spec_url)` → cached forever in `filesDir`
2. Spec invalidated only when index `version` bumps

---

## Catalog index entry

`catalog_index.json` is a single file:

```json
{
  "version": 47,
  "updated_at": "2026-04-25T13:00:00Z",
  "items": [
    {
      "id": "volcano_dragon",
      "type": "canvas_scene",
      "schema": 1,
      "title": {"en": "Volcano Dragon", "es": "Dragón del Volcán"},
      "preview_url": "https://.../volcano_dragon_preview.webp",
      "tags": ["fantasy", "fire", "epic"],
      "category": "fantasy",
      "featured": true,
      "spec_url": "https://.../wallpaper-scenes/volcano_dragon.json",
      "min_app_version": "1.7.0"
    }
  ]
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Globally unique. Snake_case. |
| `type` | enum | yes | See **Type Registry** below. |
| `schema` | int | yes | Schema version of the spec. App filters via capability registry. |
| `title` | `{lang: string}` | yes | Min `en` + `es`. |
| `preview_url` | url | yes | WebP, 540×1170 max, <80 KB. |
| `tags` | `[string]` | no | For search/filter. |
| `category` | enum | no | `fantasy` `nature` `cyber` `cute` `dark` `cosmic` `wellness` |
| `featured` | bool | no | Featured row eligibility. |
| `spec_url` | url | conditional | Required for `canvas_scene` and `shader_scene`. Static wallpapers/videos can omit (asset URL is enough). |
| `min_app_version` | string | no | Hide from older clients. |

---

## Type Registry (v1 supported)

| `type` | `schema` | Renderer (Kotlin) | Description |
|---|---|---|---|
| `static_wallpaper` | 1 | (no renderer) | Plain image, set as wallpaper directly. |
| `panoramic_wallpaper` | 1 | `PixoraWallpaperService.panoramic` | Wide bitmap, scrollable on home pages. |
| `video_wallpaper` | 1 | `PixoraWallpaperService.video` | MP4 H.264 looped. |
| `canvas_scene` | 1 | `CanvasSceneRenderer` (data-driven) | Background + sprites + particles + events, all from spec. |
| `shader_scene` | 1 | `ShaderSceneRenderer` (data-driven, ES 3.0) | GLSL fragment shader + uniforms + optional sprites. |
| `day_cycle` | 1 | `DayCycleRenderer` | 4 images switched by hour. |
| `story` | 1 | `StoryRenderer` | Sequential frames, tap-to-next. |
| `ringtone` | 1 | (audio only) | MP3 + metadata. |
| `aura_track` | 1 | `AuraPlayerService` | Audio with sleep timer + loop. |

**Forward compat**: clients silently drop items whose `(type, schema)` they don't recognize. Old clients keep working when you ship new types.

---

## `canvas_scene` spec

For sprites + particle FX wallpapers (Volcano Dragon, Dusk Fortress, Aquarium, Pixora Island…). Renderer = Canvas-based, no GL.

```json
{
  "schema_version": 1,
  "id": "volcano_dragon",
  "type": "canvas_scene",
  "title": {"en": "Volcano Dragon", "es": "Dragón del Volcán"},

  "background": {
    "url": "https://.../pixora_volcano_dragon.webp",
    "scroll": false
  },

  "sprites": [
    {
      "name": "dragon_main",
      "manifest_key": "v160_sprites/dragon_main",
      "behavior": "orbit",
      "default_facing": "right",
      "params": {
        "cx": 0.5, "cy": 0.45,
        "radius_x": 0.32, "radius_y": 0.192,
        "angular_speed": 0.012,
        "scale": 0.0014,
        "alpha": 255
      }
    }
  ],

  "particles": [
    {
      "kind": "embers",
      "params": {
        "spawn_x": 0.5, "spawn_y": 0.45,
        "spread_x": 0.06, "spread_y_jitter_px": 18,
        "count": 36,
        "speed": 1.8, "angular_spread": 0.6,
        "colors": ["#FFB040", "#FF8820", "#FFCC60", "#FF6A10"]
      }
    }
  ],

  "events": [
    {"kind": "phoenix", "interval_s": 25, "duration_s": 5,
     "sprite": "phoenix",
     "params": {"y_start": 0.95, "y_end": 0.20, "x": 0.5}},
    {"kind": "lightning_procedural", "interval_s": 10, "duration_s": 2}
  ]
}
```

### Sprite behaviors (vocabulary cerrado v1)

| `behavior` | Required `params` | Description |
|---|---|---|
| `orbit` | `cx, cy, radius_x, radius_y, angular_speed, scale` | Sprite orbits a point. Optional `start_angle`. |
| `wander` | `anchors:[[x,y],…], wander_amplitude:[ax,ay], scale` | Sprite gently drifts around fixed points. |
| `translate` | `from:[x,y], to:[x,y], duration_s, scale` | Linear motion, loops. |
| `static` | `x, y, scale` | Fixed position, just animates frames. |
| `preload` | (none) | Loads frames into RAM but draws nothing. Use this for sprites that ONLY appear inside an event (phoenix, lightning_sprite, bat_swarm) — keeps the sprite list explicit + cacheable. |

### Particle kinds (vocabulary cerrado v1)

| `kind` | `params` | Description |
|---|---|---|
| `embers` | `spawn_x/y, spread_x, count, speed, colors` | Rising hot particles with fade. |
| `motes` | `count, drift, vy, color` | Slow-rising specks (ash, dust). |
| `bubbles` | `spawn_y_min, count, speed, size_range` | Rising spheres with wobble. |
| `snow` | `count, fall_speed, drift, size_range` | Falling flakes. |
| `rain` | `count, density, angle_deg, length_px` | Diagonal streaks. |
| `wisps` | `anchors:[[x,y],…], color, radius, wobble_amplitude` | Fixed-position glowing orbs with subtle wobble. Valley fog, lantern halos, mystic lights. |
| `glass_drops` | `count, size_min/max_px, color, spawn_top/bottom, fall_speed, trail, wobble_px, sit_min/max_s` | Water droplets sitting on the screen surface, sliding down with gravity, leaving wet trails. "Rain on a window" effect. |
| `fireflies` | `count, size_min/max_px, halo_mul, color, pulse_speed, drift_amp, vy_min/max, spawn_top/bottom` | Glowing pulsing particles drifting upward. Bright core + soft radial halo. For night forests, magic gardens, fairy scenes. |

### Event kinds (vocabulary cerrado v1)

| `kind` | `params` | Description |
|---|---|---|
| `phoenix` | `sprite, x, y_start, y_end, scale_curve` | One-shot rising sprite with alpha fade. |
| `lightning_procedural` | (none) | Code-drawn jagged bolts. |
| `lightning_sprite` | `sprite, x, y, scale` | Plays a sprite once. |
| `bat_swarm` | `origin:[x,y], count, fan_angle_deg, duration_s` | Sprites fan out from a point. |
| `flash_overlay` | `color, peak_alpha, fade_s` | Full-screen flash. |

---

## `shader_scene` spec

For GL fragment-shader-driven wallpapers (Aurora Borealis, Volcano HD, future weather/snow/etc). Renderer = `ShaderSceneRenderer` on OpenGL ES 3.0.

```json
{
  "schema_version": 1,
  "id": "snow_blizzard",
  "type": "shader_scene",
  "title": {"en": "Snow Blizzard", "es": "Tormenta de Nieve"},

  "shader_url": "https://.../wallpaper-shaders/snow_blizzard.glsl",
  "background_url": "https://.../snow_landscape.webp",

  "uniforms": {
    "uIntensity":  {"type": "float", "value": 0.7},
    "uColor":      {"type": "vec3",  "value": [0.92, 0.96, 1.0]},
    "uWindSpeed":  {"type": "float", "value": 0.3},
    "uFlakeCount": {"type": "int",   "value": 200}
  },

  "sprites": [],
  "events": []
}
```

### Auto-bindeados (Tier 1) — every shader gets these for free

If the shader doesn't declare these uniforms, the engine doesn't fail; it just doesn't bind them. Cost: ~zero per frame.

| Uniform | GLSL type | Source |
|---|---|---|
| `uTime` | `float` | Seconds since shader started. |
| `uDeltaTime` | `float` | Seconds since previous frame. |
| `uResolution` | `vec2` | Pixels (width, height). |
| `uAspect` | `float` | width / height. |
| `uPixelRatio` | `float` | Device pixel density (1, 2, 3). |
| `uScrollOffset` | `float` | 0..1 home-page swipe. Native parallax. |
| `uIsLockScreen` | `float` | 0 = home, 1 = lock. |
| `uIsVisible` | `float` | 0 when hidden (notif tray). Engine pauses too. |
| `uTouchX` | `float` | Last touch X normalized 0..1. |
| `uTouchY` | `float` | Last touch Y normalized 0..1. |
| `uHour` | `int` | 0..23. |
| `uMinute` | `int` | 0..59. |
| `uDayOfYear` | `int` | 1..365. |
| `uSafeAreaTop` | `float` | Status-bar height in normalized px. |
| `uSafeAreaBottom` | `float` | Nav-bar height in normalized px. |
| `uTex` | `sampler2D` | Background texture (if `background_url` set). |

### Sensor-derived (Tier 2) — opt-in via `requires_permissions`

Add these to the spec to request them. If user denies (or the sensor is missing), the uniform stays at 0.

```json
"requires_permissions": ["sensor.gyro", "sensor.light"],
"uniforms_sensors": ["uOrientation", "uLightLevel"]
```

| Uniform | GLSL type | Permission key | Source |
|---|---|---|---|
| `uOrientation` | `vec3` | `sensor.gyro` | pitch, yaw, roll (radians) |
| `uAcceleration` | `vec3` | `sensor.accel` | x, y, z (m/s²) |
| `uLightLevel` | `float` | `sensor.light` | lux normalized 0..1 |
| `uIsCharging` | `float` | (none) | 0 / 1 |
| `uBattery` | `float` | (none) | 0..1 |
| `uHasNotifications` | `float` | `notif.listener` | 0 / 1 (heavy — only if needed) |

### Custom uniforms (Tier 4) — declared per-scene

Anything else lives in `"uniforms"`. Supported types: `float`, `vec2`, `vec3`, `vec4`, `int`, `mat4`. The engine binds them by name+type once at shader-load time.

---

## Branding signature (Pixora "P" 3D logo)

Every `canvas_scene` automatically renders the gold "P" logo spinning in
3D (Y-axis rotation via `android.graphics.Camera.rotateY()`) at the
bottom-right by default. Inspired by the RARE N64 intro.

Override via the optional top-level `branding` block:

```json
"branding": {
  "enabled": true,           // default true
  "x": 0.92,                 // normalized 0..1, default 0.92 (right edge)
  "y": 0.945,                // normalized 0..1, default 0.945 (where Gemini watermark used to live)
  "size": 0.07,              // fraction of surface width, default 0.07
  "rotation_speed": 0.020    // radians/frame; 0.020 ≈ one rev per ~5 seconds
}
```

To disable on a scene where the brand mark would clash:

```json
"branding": { "enabled": false }
```

---

## Versioning rules

- **Bumping `schema_version`** = breaking change. New + old clients coexist; old ones drop your new items.
- **Adding optional fields** to an existing schema = NOT a bump. Old clients ignore unknown fields.
- **Adding a new `behavior`/`kind`/`type`** = NOT a bump. Old clients drop only items that USE the unknown vocabulary; the rest of the catalog still works.
- **Bump only when removing/renaming a required field** or changing its semantics.

---

## Capability Registry (Dart)

```dart
class CapabilityRegistry {
  static const supported = <String, List<int>>{
    'static_wallpaper':    [1],
    'panoramic_wallpaper': [1],
    'video_wallpaper':     [1],
    'canvas_scene':        [1],
    'shader_scene':        [1],
    'day_cycle':           [1],
    'story':               [1],
    'ringtone':            [1],
    'aura_track':          [1],
  };

  static const knownBehaviors = <String>{'orbit','wander','translate','static'};
  static const knownParticles = <String>{'embers','motes','bubbles','snow','rain'};
  static const knownEvents    = <String>{
    'phoenix','lightning_procedural','lightning_sprite','bat_swarm','flash_overlay',
  };

  static bool itemSupported(Map<String,dynamic> indexEntry) {
    final t = indexEntry['type'] as String?;
    final s = indexEntry['schema'] as int?;
    if (t == null || s == null) return false;
    return supported[t]?.contains(s) ?? false;
  }

  static bool sceneSupported(Map<String,dynamic> spec) {
    // Validate every behavior/particle/event vocabulary
    for (final sp in (spec['sprites'] as List? ?? [])) {
      if (!knownBehaviors.contains(sp['behavior'])) return false;
    }
    for (final p in (spec['particles'] as List? ?? [])) {
      if (!knownParticles.contains(p['kind'])) return false;
    }
    for (final e in (spec['events'] as List? ?? [])) {
      if (!knownEvents.contains(e['kind'])) return false;
    }
    return true;
  }
}
```

When a client encounters unknown vocabulary inside an otherwise-valid spec, it should **hide the entire item** (better than rendering a broken version).

---

## Adding new content checklist

1. **New wallpaper of an EXISTING type** (e.g. another `canvas_scene`):
   - Upload assets (background.webp + sprite ZIPs) to their buckets
   - Write `<id>.json` spec
   - Upload to `wallpaper-scenes/<id>.json`
   - Append to `catalog_index.json`, bump `version`
   - **No app update required.**

2. **New shader effect**:
   - Upload `<name>.glsl` to `wallpaper-shaders/`
   - Write `<id>.json` spec referencing it + uniforms
   - Same as above — append to index, bump version
   - **No app update required.**

3. **New behavior/particle/event vocabulary**:
   - Add Kotlin code to `CanvasSceneRenderer` to handle it
   - Add to Dart `CapabilityRegistry.knownBehaviors/Particles/Events`
   - Ship app update
   - Old clients drop items using the new vocabulary; new clients render them.

4. **New `type` (e.g. `gltf_3d_scene`)**:
   - Build the renderer
   - Add to Dart `CapabilityRegistry.supported`
   - Ship app update
   - Old clients drop items of that type; new clients render them.
