precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

vec2 rot2(vec2 p, float a){ float c = cos(a), s = sin(a); return mat2(c, -s, s, c) * p; }

float circleOutline(vec2 p, vec2 c, float r, float w){
  return smoothstep(w, 0.0, abs(length(p - c) - r));
}

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;
  float t = mod(uTime, 60.0);
  float rotSpeed = 0.15 + uPressed * 0.8;
  uv = rot2(uv, mod(t * rotSpeed, 6.2831853));

  vec3 col = vec3(0.04, 0.02, 0.08);
  float r = 0.18;
  float w = 0.005;
  float glow = 0.0;

  // 7 central seed circles (Flower of Life)
  for (int i = 0; i < 7; i++){
    float ang = float(i) * 6.2831853 / 6.0;
    vec2 c = i == 0 ? vec2(0.0) : vec2(cos(ang), sin(ang)) * r;
    glow += circleOutline(uv, c, r, w);
  }

  // 6 outer ring
  for (int i = 0; i < 6; i++){
    float ang = float(i) * 6.2831853 / 6.0 + 3.1415926 / 6.0;
    vec2 c = vec2(cos(ang), sin(ang)) * r * 1.7320508;
    glow += circleOutline(uv, c, r, w) * 0.7;
  }

  // Expanding pulse ring
  float pulseR = mod(t * 0.25, 1.0);
  float pulse = exp(-abs(length(uv) - pulseR) * 25.0) * 0.7;

  vec3 gold = vec3(1.0, 0.85, 0.45);
  vec3 violetCol = vec3(0.7, 0.4, 1.0);
  vec3 tint = mix(gold, violetCol, 0.5 + 0.5 * sin(mod(t * 0.4, 6.2831853)));

  col += tint * glow * 1.4;
  col += tint * pulse * 0.6;

  // Touch halo (in rotated frame)
  vec2 mouseUv = (uMouse * uResolution.xy - 0.5 * uResolution.xy) / uResolution.y;
  mouseUv = rot2(mouseUv, mod(t * rotSpeed, 6.2831853));
  float md = length(uv - mouseUv);
  float halo = exp(-md * 4.0) * uPressed * 1.5;
  col += vec3(1.0, 0.9, 0.6) * halo;

  gl_FragColor = vec4(col, 1.0);
}
