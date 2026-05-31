precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash11(float p){ return fract(sin(p * 78.233) * 43758.5453); }

vec3 starColor(float h){
  if (h < 0.20) return vec3(1.0, 0.35, 0.20);
  if (h < 0.40) return vec3(1.0, 0.65, 0.25);
  if (h < 0.65) return vec3(1.0, 0.95, 0.60);
  if (h < 0.85) return vec3(0.92, 0.95, 1.0);
  return vec3(0.55, 0.75, 1.0);
}

void main(){
  vec2 uv = gl_FragCoord.xy / uResolution.xy;
  float t = mod(uTime, 60.0);
  vec3 col = vec3(0.005, 0.008, 0.015) * (1.0 - uv.y * 0.5);

  for (int layer = 0; layer < 3; layer++){
    float scale = 22.0 + float(layer) * 35.0;
    vec2 gridUV = uv * scale;
    vec2 id = floor(gridUV);
    vec2 cellUV = fract(gridUV) - 0.5;
    float h = hash(id + float(layer) * 17.0);
    if (h > 0.95) {
      float starSize = 0.04 + (h - 0.95) * 1.4;
      float dist = length(cellUV);
      // Independent twinkle per star — use a different hash that spans full
      // (0..1) range so speed AND phase truly differ between stars (vs h which
      // is clamped to (0.95..1) by the gate above and would sync them all).
      float twSpeed = hash(id + 31.7);   // 0..1
      float twPhase = hash(id - 5.1);    // 0..1
      float twinkleArg = mod(t * (0.6 + twSpeed * 2.8) + twPhase * 6.2831853, 6.2831853);
      float twinkle = 0.5 + 0.5 * sin(twinkleArg);
      float core = smoothstep(starSize, 0.0, dist);
      float halo = smoothstep(starSize * 4.0, 0.0, dist) * 0.25;
      vec3 c = starColor(hash(id - 7.3));
      col += c * (core + halo) * (0.25 + twinkle * 0.75) * (1.0 - float(layer) * 0.18);
    }
  }

  // Shooting star — periodic
  float shootT = mod(t * 0.4, 1.0);
  vec2 shootStart = vec2(hash(vec2(floor(t * 0.4), 1.0)), 1.0);
  vec2 shootEnd   = vec2(shootStart.x + 0.35, 0.45);
  vec2 sp = mix(shootStart, shootEnd, shootT);
  float sd = length(uv - sp);
  vec2 dir = normalize(shootEnd - shootStart);
  float along = dot(uv - sp, -dir);
  float trail = exp(-sd * 50.0) * smoothstep(0.0, 0.12, along) * exp(-along * 6.0);
  col += vec3(0.9, 0.95, 1.0) * trail * 2.0;

  // Touch: comet from finger
  vec2 m = uMouse;
  float md = length(uv - m);
  float comet = exp(-md * 7.0) * uPressed;
  col += vec3(0.7, 0.9, 1.0) * comet * 1.2;

  gl_FragColor = vec4(col, 1.0);
}
