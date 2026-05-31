precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p){
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i),               hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 hexCoord(vec2 p, out vec2 id){
  vec2 s = vec2(1.0, 1.7320508);
  vec4 hC = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
  vec4 h  = vec4(p - hC.xy * s, p - (hC.zw + 0.5) * s);
  vec4 winner = dot(h.xy, h.xy) < dot(h.zw, h.zw)
              ? vec4(h.xy, hC.xy)
              : vec4(h.zw, hC.zw + 0.5);
  id = winner.zw;
  return winner.xy;
}

float hexDist(vec2 p){
  p = abs(p);
  return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

// Full-spectrum cosine palette — every hue reachable. Drives the per-hex
// color picker for vibrant, varied output instead of just violet→cyan.
// Args explicitly wrapped to [0, 2π) to keep cos precision tight.
vec3 palette(float t){
  vec3 args = mod(6.2831853 * (t + vec3(0.0, 0.33, 0.67)), 6.2831853);
  return 0.5 + 0.5 * cos(args);
}

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;
  // Time wrapped to 60s so sin/cos arguments stay tiny even after hours of
  // continuous rendering — no precision drift, no banding artifacts.
  float t = mod(uTime, 60.0);

  // Higher scale = smaller hexes = denser honeycomb.
  float SCALE = 11.0;
  vec2 scaled = uv * SCALE;
  vec2 myId;
  vec2 cellUv = hexCoord(scaled, myId);
  float edge = hexDist(cellUv);

  // ── Per-hex independent pulse (own speed + phase) ────────────────
  float seed = hash(myId);
  float phase = hash(myId + 7.3) * 6.2831853;
  float speed = 0.4 + seed * 1.8;
  float pulseArg = mod(t * speed + phase, 6.2831853);
  float energy = 0.5 + 0.5 * sin(pulseArg);

  // ── TOUCH: light up the EXACT hex under the finger ───────────────
  // Same hexCoord transform with same SCALE so IDs are directly comparable.
  vec2 mouseUv = (uMouse * uResolution.xy - 0.5 * uResolution.xy) / uResolution.y;
  vec2 touchScaled = mouseUv * SCALE;
  vec2 touchId;
  hexCoord(touchScaled, touchId);

  // step-based equality is robust against vec2 == in older GLSL ES.
  float idMatch = step(abs(myId.x - touchId.x), 0.01)
                * step(abs(myId.y - touchId.y), 0.01);
  float touchPress = idMatch * uPressed;
  energy = max(energy, touchPress);

  float lit = smoothstep(0.55, 0.90, energy);

  // ── Color: full-spectrum per hex with slow time-drift on hue ─────
  float colorSeed = hash(myId + 1.7);
  // Slow drift adds aliveness without changing too fast (0.02 cycles/sec).
  vec3 hexColor = palette(colorSeed + t * 0.02);
  vec3 sparkColor = vec3(0.95, 0.98, 1.0);
  vec3 white = vec3(1.0);

  vec3 col = vec3(0.012, 0.018, 0.045);

  // Always-visible dim grid (structure readable when dark)
  float dimBorder = smoothstep(0.50, 0.49, edge) - smoothstep(0.47, 0.46, edge);
  col += vec3(0.15, 0.20, 0.35) * dimBorder * 0.45;

  // Cell core glow proportional to energy
  float cellGlow = smoothstep(0.45, 0.05, edge);
  col += hexColor * cellGlow * lit * 0.55;

  // Lit hex IGNITES its border bright
  float litBorder = smoothstep(0.50, 0.46, edge) - smoothstep(0.46, 0.42, edge);
  col += hexColor * litBorder * lit * 2.2;

  // ── Touch-pressed hex: WHITE-HOT premium feedback ───────────────
  // Specific hex gets bright white core + halo so the user sees CLEARLY
  // which one their finger is on.
  col += white * cellGlow * touchPress * 0.9;
  col += white * litBorder * touchPress * 2.5;

  // Soft glow extending slightly beyond the touched hex (radial halo so it
  // feels alive, not like a stamp).
  float touchHalo = exp(-length(uv - mouseUv) * 8.0) * uPressed * 0.5;
  col += hexColor * touchHalo;

  // ── High-frequency electric crackle on lit borders ──────────────
  float flickerArg = mod(t * 35.0 + seed * 100.0, 6.2831853);
  float flicker = 0.65 + 0.35 * sin(flickerArg);
  col += sparkColor * litBorder * lit * flicker * 0.65;

  // ── Drifting electric field — sparks flow ACROSS the grid ───────
  // Two layered noise drifts at different speeds/scales = current flowing
  // visibly from hex to hex via border zones.
  vec2 driftA = uv * 3.0 + vec2(t * 0.40, t * 0.20);
  vec2 driftB = uv * 5.5 - vec2(t * 0.35, t * 0.55);
  float fieldA = noise(driftA);
  float fieldB = noise(driftB);
  float spark = smoothstep(0.78, 0.97, fieldA)
              + smoothstep(0.82, 0.97, fieldB) * 0.5;
  float borderZone = smoothstep(0.30, 0.50, edge);
  col += sparkColor * spark * borderZone * 1.3;
  col += sparkColor * spark * borderZone * lit * 0.7;

  gl_FragColor = vec4(col, 1.0);
}
