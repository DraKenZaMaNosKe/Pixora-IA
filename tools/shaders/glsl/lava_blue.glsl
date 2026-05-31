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
    float seed = hash(vec2(fi, 1.7));
    float cycle = mod(t * 0.07 + fi * 2.3, 6.0);
    float ramp = 1.0 - abs(cycle - 3.0) / 3.0;
    ramp = smoothstep(0.0, 1.0, ramp);
    float y = -0.45 + ramp * 0.90;
    float x = (seed - 0.5) * 0.32 + sin(mod(t * 0.18 + fi * 1.3, 6.2831853)) * 0.04;
    vec2 pos = vec2(x, y);
    float rRad = 0.07 + seed * 0.04;
    float dist = length((uv - pos) * vec2(aspect, 1.0));
    float contribution = rRad * rRad / (dist * dist + 0.002);
    field += contribution;
    float heat = y + 0.5;
    vec3 c = mix(vec3(0.08, 0.30, 0.95), vec3(0.25, 0.90, 1.0), heat);
    lavaCol += c * contribution;
  }

  vec3 bg = mix(vec3(0.01, 0.02, 0.08), vec3(0.03, 0.06, 0.14), uv.y + 0.5);
  float surface = smoothstep(0.85, 1.30, field);
  vec3 col = mix(bg, lavaCol / max(field, 0.001), surface);
  float halo = smoothstep(0.40, 0.85, field) * 0.40;
  col += vec3(0.20, 0.70, 1.0) * halo;

  col = col / (1.0 + col * 0.40);
  gl_FragColor = vec4(col, 1.0);
}
