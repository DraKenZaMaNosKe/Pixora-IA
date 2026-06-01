import 'realm_shader.dart';

/// Hardcoded REALM shader catalog (v1, shipped 2026-05-31).
///
/// 10 abstract designs + 1 analog clock. All shaders live in the
/// `wallpaper-shaders` bucket as <id>.glsl, downloaded on demand by
/// `ShaderDownloadService`. Previews are pre-uploaded to
/// `wallpaper-images/realm_previews/<id>.webp` (12-37 KB each).
///
/// To add a new shader:
///   1. Drop <id>.glsl into tools/shaders/glsl/
///   2. python tools/pixora_publish.py shader tools/shaders/glsl/<id>.glsl
///   3. Generate a preview WebP (1080×2034-ish, q=82) and upload to
///      wallpaper-images/realm_previews/<id>.webp
///   4. Add the entry below
///   5. Add id to ShaderDownloadService._bootstrap so it pre-caches
///
/// Order matters — entries render top-to-bottom in their category.
class RealmCatalog {
  RealmCatalog._();

  static const List<RealmShader> all = [
    // ── Abstract / decorative ──────────────────────────────────────
    RealmShader(
      id: 'universe',
      name: 'Universe',
      description:
          'Cosmos infinito con estrellas de colores reales según su temperatura. Cometa al tocar.',
      category: RealmCategory.abstract_,
      glowColor: '#00E5FF',
      previewKey: 'realm_previews/universe.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'honeycomb',
      name: 'Honeycomb',
      description:
          'Grid hexagonal neón con onda de brillo. Hexes se incendian donde tocas.',
      category: RealmCategory.abstract_,
      glowColor: '#9D4EDD',
      previewKey: 'realm_previews/honeycomb.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'neon_triangles',
      name: 'Neon Triangles',
      description:
          'Pantalla teselada en triángulos respirando colores neón. Ripple al tocar.',
      category: RealmCategory.abstract_,
      glowColor: '#FF00CC',
      previewKey: 'realm_previews/neon_triangles.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'sacred_geometry',
      name: 'Sacred Geometry',
      description:
          'Flor de la vida rotando con líneas doradas. Halo radial al tocar.',
      category: RealmCategory.abstract_,
      glowColor: '#FFD66B',
      previewKey: 'realm_previews/sacred_geometry.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'digital_rain',
      name: 'Digital Rain',
      description:
          'Matrix-style caracteres cayendo en columnas. Tu dedo vuelve rojas las cercanas.',
      category: RealmCategory.abstract_,
      glowColor: '#33FF99',
      previewKey: 'realm_previews/digital_rain.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'synthwave_grid',
      name: 'Synthwave Grid',
      description:
          'Rejilla retro 80s recediendo al horizonte con sol cuadriculado. Rayos al tocar.',
      category: RealmCategory.abstract_,
      glowColor: '#FF3478',
      previewKey: 'realm_previews/synthwave_grid.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'plasma_orbs',
      name: 'Plasma Orbs',
      description:
          'Esferas de luz flotando, colores se mezclan como lava lamp moderno. Nueva orb sigue tu dedo.',
      category: RealmCategory.abstract_,
      glowColor: '#C77DFF',
      previewKey: 'realm_previews/plasma_orbs.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'kaleidoscope',
      name: 'Kaleidoscope',
      description:
          'Mandala mirrored en 6 ejes, colores que cambian con tiempo. Centro se mueve a tu dedo.',
      category: RealmCategory.abstract_,
      glowColor: '#FF8FBE',
      previewKey: 'realm_previews/kaleidoscope.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'metaballs',
      name: 'Metaballs',
      description:
          'Gotas líquidas que se fusionan y separan, lámpara de lava cyber. Nueva gota al tocar.',
      category: RealmCategory.abstract_,
      glowColor: '#00E5FF',
      previewKey: 'realm_previews/metaballs.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'circuit_city',
      name: 'Circuit City',
      description:
          'Circuito electrónico glowing con pulsos viajando. Pulso radial desde tu dedo.',
      category: RealmCategory.abstract_,
      glowColor: '#00E5FF',
      previewKey: 'realm_previews/circuit_city.webp',
      badge: 'NEW',
    ),

    // ── Plasma & Lava (v2 pack, 2026-05-31) ──────────────────────
    RealmShader(
      id: 'cosmic_plasma',
      name: 'Cosmic Plasma',
      description:
          'Masa violeta-rosa swirling con corrientes internas. Sentimiento cósmico, slow morph.',
      category: RealmCategory.abstract_,
      glowColor: '#FF3478',
      previewKey: 'realm_previews/cosmic_plasma.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'liquid_aurora',
      name: 'Liquid Aurora',
      description:
          'Masa verde-cyan fluyendo como aurora boreal hecha líquido. Se atrae a tu dedo.',
      category: RealmCategory.abstract_,
      glowColor: '#33FF99',
      previewKey: 'realm_previews/liquid_aurora.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'galaxy_plasma',
      name: 'Galaxy Plasma',
      description:
          'Plasma con distorsión espiral interna — parece galaxia girando con brazos visibles.',
      category: RealmCategory.abstract_,
      glowColor: '#C77DFF',
      previewKey: 'realm_previews/galaxy_plasma.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'lava_red',
      name: 'Classic Red Lava',
      description:
          'Lámpara de lava clásica — burbujas rojas/naranjas suben en líquido cream. Touch acelera.',
      category: RealmCategory.abstract_,
      glowColor: '#FF6B35',
      previewKey: 'realm_previews/lava_red.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'lava_blue',
      name: 'Cool Blue Lava',
      description:
          'Lava azul-cyan en vidrio oscuro nocturno. Vibe relajante de noche.',
      category: RealmCategory.abstract_,
      glowColor: '#00B4FF',
      previewKey: 'realm_previews/lava_blue.webp',
      badge: 'NEW',
    ),
    RealmShader(
      id: 'lava_pastel',
      name: 'Pastel Lava',
      description:
          'Burbujas rosa-lavanda-melocotón en líquido crema pastel. Aesthetic kawaii / cottage core.',
      category: RealmCategory.abstract_,
      glowColor: '#FFB6D9',
      previewKey: 'realm_previews/lava_pastel.webp',
      badge: 'NEW',
    ),

    // ── Hybrid texture lamps (real lamp body + animated blobs) ──
    RealmShader(
      id: 'lava_hot_pink',
      name: 'Hot Pink Lamp',
      description:
          'Lámpara real con burbujas rosa-magenta fluyendo dentro del tubo. Combina foto premium + blobs animados en tiempo real.',
      category: RealmCategory.abstract_,
      glowColor: '#FF3478',
      previewKey: 'realm_previews/lava_hot_pink.webp',
      badge: 'NEW',
    ),

    // ── Clocks ────────────────────────────────────────────────────
    RealmShader(
      id: 'clock',
      name: 'Classic Analog',
      description:
          'Reloj analógico con manecillas en tiempo real, segundero suave. Halo al tocar.',
      category: RealmCategory.clock,
      glowColor: '#7C4DFF',
      previewKey: 'realm_previews/clock.webp',
      badge: 'NEW',
    ),
  ];

  static List<RealmShader> get abstracts =>
      all.where((s) => s.category == RealmCategory.abstract_).toList();

  static List<RealmShader> get clocks =>
      all.where((s) => s.category == RealmCategory.clock).toList();
}
