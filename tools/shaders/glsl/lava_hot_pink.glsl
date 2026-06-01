precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;       // unused
uniform float uPressed;     // unused
uniform sampler2D uSkin;    // lava lamp body texture
uniform float uHasSkin;     // > 0.5 when uSkin is bound

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 renderBlobs(vec2 uv, float t, float aspect, bool useDarkBg){
  float field = 0.0;
  vec3 lavaCol = vec3(0.0);
  for (int i = 0; i < 6; i++){
    float fi = float(i);
    float seed = hash(vec2(fi, 0.0));
    float cycle = mod(t * 0.07 + fi * 2.3, 6.0);
    float ramp = 1.0 - abs(cycle - 3.0) / 3.0;
    ramp = smoothstep(0.0, 1.0, ramp);
    float y = -0.45 + ramp * 0.90;
    float x = (seed - 0.5) * 0.32
            + sin(mod(t * 0.18 + fi * 1.3, 6.2831853)) * 0.04;
    vec2 pos = vec2(x, y);
    float rRad = 0.07 + seed * 0.04;
    float dist = length((uv - pos) * vec2(aspect, 1.0));
    float contribution = rRad * rRad / (dist * dist + 0.002);
    field += contribution;
    float heat = y + 0.5;
    // Hot-pink palette: deep magenta at bottom → bright pink at top
    vec3 hot  = vec3(0.85, 0.05, 0.45);
    vec3 cool = vec3(1.0,  0.65, 0.85);
    vec3 c = mix(hot, cool, heat);
    lavaCol += c * contribution;
  }
  vec3 bg = useDarkBg
      ? mix(vec3(0.20, 0.04, 0.12), vec3(0.35, 0.10, 0.20), uv.y + 0.5)
      : vec3(0.45, 0.08, 0.25);
  float surface = smoothstep(0.85, 1.30, field);
  vec3 col = mix(bg, lavaCol / max(field, 0.001), surface);
  float halo = smoothstep(0.40, 0.85, field) * 0.45;
  col += vec3(1.0, 0.45, 0.70) * halo;
  return col / (1.0 + col * 0.30);
}

void main(){
  vec2 fragUv = gl_FragCoord.xy / uResolution.xy;
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;
  float t = mod(uTime, 60.0);
  float aspect = uResolution.x / uResolution.y;

  if (uHasSkin > 0.5) {
    vec3 skinCol = texture2D(uSkin, vec2(fragUv.x, 1.0 - fragUv.y)).rgb;
    bool insideTube =
        skinCol.r > 0.85 && skinCol.g < 0.20 && skinCol.b > 0.85;
    if (insideTube) {
      gl_FragColor = vec4(renderBlobs(uv, t, aspect, false), 1.0);
    } else {
      gl_FragColor = vec4(skinCol, 1.0);
    }
  } else {
    gl_FragColor = vec4(renderBlobs(uv, t, aspect, true), 1.0);
  }
}
