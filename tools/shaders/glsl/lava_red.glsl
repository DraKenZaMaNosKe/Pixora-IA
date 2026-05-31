precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;     // unused — lava lamps stay natural
uniform float uPressed;   // unused

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5*uResolution.xy)/uResolution.y;
  float t = mod(uTime, 60.0);
  float aspect = uResolution.x/uResolution.y;

  // 6 SMALL blobs (radius 0.07-0.11) clearly separated. Triangle-wave
  // vertical motion with smooth ease in/out — slow at top/bottom like
  // real lava-lamp wax cooling and dropping.
  float field = 0.0;
  vec3 lavaCol = vec3(0.0);
  for (int i = 0; i < 6; i++){
    float fi = float(i);
    float seed = hash(vec2(fi, 0.0));
    float cycle = mod(t * 0.07 + fi * 2.3, 6.0);
    float ramp = 1.0 - abs(cycle - 3.0) / 3.0;
    ramp = smoothstep(0.0, 1.0, ramp);
    float y = -0.45 + ramp * 0.90;
    // X spread within visible portrait area (±0.18 ≈ phone uv.x range)
    float x = (seed - 0.5) * 0.32 + sin(mod(t * 0.18 + fi * 1.3, 6.2831853)) * 0.04;
    vec2 pos = vec2(x, y);
    float rRad = 0.07 + seed * 0.04;   // 0.07 to 0.11 — SMALL
    float dist = length((uv - pos) * vec2(aspect, 1.0));
    float contribution = rRad * rRad / (dist * dist + 0.002);
    field += contribution;
    // Color: red bottom → yellow top
    float heat = y + 0.5;
    vec3 c = mix(vec3(1.0, 0.20, 0.05), vec3(1.0, 0.85, 0.30), heat);
    lavaCol += c * contribution;
  }

  // Background: warm amber gradient
  vec3 bg = mix(vec3(0.32, 0.10, 0.04), vec3(0.50, 0.25, 0.08), uv.y + 0.5);

  // Higher threshold so only blob CORES show fully, edges fade naturally
  float surface = smoothstep(0.85, 1.30, field);
  vec3 col = mix(bg, lavaCol / max(field, 0.001), surface);

  // Tight halo around blobs (heat radiating just at the edge)
  float halo = smoothstep(0.40, 0.85, field) * 0.40;
  col += vec3(1.0, 0.55, 0.20) * halo;

  col = col / (1.0 + col * 0.30);
  gl_FragColor = vec4(col, 1.0);
}
