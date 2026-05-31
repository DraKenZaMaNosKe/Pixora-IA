precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash11(float p){ return fract(sin(p * 78.233) * 43758.5453); }

// Procedural glyph — divides cell into a 3×5 pixel matrix, each sub-pixel
// on/off based on hash. Mimics Matrix katakana/digit characters without
// needing a font texture. Cell padding keeps glyphs from touching edges.
float glyph(vec2 cellLocalUv, float seed){
  vec2 q = (cellLocalUv - vec2(0.12, 0.05)) / vec2(0.76, 0.90);
  // Inside the inset rect?
  vec2 inside = step(0.0, q) * step(q, vec2(1.0));
  if (inside.x * inside.y < 0.5) return 0.0;
  vec2 sub = floor(q * vec2(3.0, 5.0));
  // Bound seed to avoid runaway hash inputs.
  float wrappedSeed = mod(seed, 200.0);
  return step(0.40, hash(sub * 13.0 + vec2(wrappedSeed)));
}

void main(){
  vec2 uv = gl_FragCoord.xy / uResolution.xy;
  float t = mod(uTime, 60.0);

  // Smaller cells = denser rain. 50 cols × 90 rows on 1080×2340 →
  // ~21×26 px per cell, glyphs ~7×13 px → readable but tight.
  vec2 GRID = vec2(50.0, 90.0);
  vec2 gridUv = uv * GRID;
  vec2 cellId = floor(gridUv);
  vec2 cellLocalUv = fract(gridUv);

  // Per-column character: speed + staggered start so columns don't sync.
  float colSeed = hash11(cellId.x * 7.13);
  float speed = 0.35 + colSeed * 1.0;
  float delay = colSeed * 6.0;

  // Drop head Y in [0..1] screen space. The "head" sweeps from top to
  // bottom and wraps. Use cycle slightly > 1.0 so trails finish off-screen
  // before the next drop starts.
  float cycle = mod(t * speed + delay, 1.55);
  float headY = 1.0 - cycle;

  // Cell's center Y vs head position (positive = cell is below head).
  float cellCenterY = (cellId.y + 0.5) / GRID.y;
  float distFromHead = headY - cellCenterY;

  // Brightness curve along the trail.
  float trailLen = 0.32;
  float bright = 0.0;
  if (distFromHead >= -0.004 && distFromHead < 0.02) {
    bright = 1.0;  // HEAD — ultra bright
  } else if (distFromHead >= 0.0 && distFromHead < trailLen) {
    bright = 1.0 - smoothstep(0.02, trailLen, distFromHead);
  }

  // Character mutates over time (4 mutations/sec per column).
  float charIdx = mod(floor(t * 4.0 + cellId.y * 0.3 + colSeed * 10.0), 100.0);
  float glyphMask = glyph(cellLocalUv,
                          hash(cellId + vec2(charIdx)) * 100.0);

  // Colors: pale white-green at head, matrix green in trail.
  vec3 head = vec3(0.85, 1.0, 0.95);
  vec3 trail = vec3(0.05, 1.0, 0.35);
  float headness = 1.0 - smoothstep(0.0, 0.025, distFromHead);
  vec3 col = mix(trail, head, headness) * bright * glyphMask;

  // ── Touch: column near finger turns RED + slightly accelerates ──
  vec2 mouseUv = uMouse;
  float colDist = abs(uv.x - mouseUv.x);
  float touchInfluence = exp(-colDist * 12.0) * uPressed;
  vec3 redTrail = vec3(1.0, 0.15, 0.25);
  col = mix(col, redTrail * bright * glyphMask, touchInfluence);

  // Subtle ambient green tint (very dim background)
  col += vec3(0.0, 0.012, 0.005);

  // CRT scanline shimmer (alternate-row brightness, very subtle)
  float scanline = 0.93 + 0.07 * step(0.5, mod(gl_FragCoord.y, 2.0));
  col *= scanline;

  gl_FragColor = vec4(col, 1.0);
}
