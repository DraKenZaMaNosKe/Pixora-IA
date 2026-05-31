precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;     // unused
uniform float uPressed;   // unused

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5*uResolution.xy)/uResolution.y;
  float t = mod(uTime, 60.0);
  float aspect = uResolution.x/uResolution.y;

  float field = 0.0;
  vec3 lavaCol = vec3(0.0);
  for (int i = 0; i < 6; i++){
    float fi = float(i);
    float seed = hash(vec2(fi, 7.1));
    float cycle = mod(t * 0.06 + fi * 2.4, 6.0);
    float ramp = 1.0 - abs(cycle - 3.0) / 3.0;
    ramp = smoothstep(0.0, 1.0, ramp);
    float y = -0.45 + ramp * 0.90;
    float x = (seed - 0.5) * 0.32 + sin(mod(t * 0.15 + fi * 1.5, 6.2831853)) * 0.04;
    vec2 pos = vec2(x, y);
    float rRad = 0.07 + seed * 0.04;
    float dist = length((uv - pos) * vec2(aspect, 1.0));
    float contribution = rRad * rRad / (dist * dist + 0.002);
    field += contribution;
    // Pastel palette per seed
    float hueShift = fract(seed + t * 0.015);
    vec3 pinkA = vec3(1.0, 0.65, 0.80);
    vec3 lavender = vec3(0.80, 0.70, 1.0);
    vec3 peach = vec3(1.0, 0.80, 0.65);
    vec3 c;
    if (hueShift < 0.33) c = pinkA;
    else if (hueShift < 0.66) c = lavender;
    else c = peach;
    lavaCol += c * contribution;
  }

  vec3 bg = mix(vec3(0.92, 0.88, 0.94), vec3(0.97, 0.93, 0.92), uv.y + 0.5);
  float surface = smoothstep(0.85, 1.30, field);
  vec3 col = mix(bg, lavaCol / max(field, 0.001), surface);
  // Soft shadow (AO feel)
  float ao = smoothstep(0.40, 0.85, field) * 0.18;
  col -= vec3(0.10, 0.10, 0.08) * ao;

  gl_FragColor = vec4(col, 1.0);
}
