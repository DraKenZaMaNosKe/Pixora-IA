precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

void main(){
  vec2 uv = gl_FragCoord.xy / uResolution.xy;
  float t = mod(uTime, 60.0);

  vec3 col = vec3(0.02, 0.01, 0.05);

  vec2 orbs[4];
  vec3 colors[4];
  orbs[0] = vec2(0.5 + 0.30 * cos(mod(t * 0.45, 6.2831853)),
                 0.5 + 0.30 * sin(mod(t * 0.45, 6.2831853)));
  orbs[1] = vec2(0.5 + 0.25 * cos(mod(t * -0.62 + 2.0, 6.2831853)),
                 0.5 + 0.32 * sin(mod(t * -0.62 + 2.0, 6.2831853)));
  orbs[2] = vec2(0.5 + 0.28 * cos(mod(t * 0.38 + 4.0, 6.2831853)),
                 0.5 + 0.20 * sin(mod(t * 0.78 + 4.0, 6.2831853)));
  orbs[3] = vec2(0.5 + 0.22 * cos(mod(t * -0.50 + 1.0, 6.2831853)),
                 0.5 + 0.28 * sin(mod(t * -0.50 + 1.0, 6.2831853)));
  colors[0] = vec3(1.0, 0.2, 0.6);
  colors[1] = vec3(0.2, 0.9, 1.0);
  colors[2] = vec3(0.8, 0.3, 1.0);
  colors[3] = vec3(1.0, 0.7, 0.2);

  float aspect = uResolution.x / uResolution.y;
  for (int i = 0; i < 4; i++){
    float d = length((uv - orbs[i]) * vec2(aspect, 1.0));
    float intensity = exp(-d * 4.5);
    col += colors[i] * intensity * 0.9;
  }

  // Touch orb
  vec2 mouseUv = uMouse;
  float md = length((uv - mouseUv) * vec2(aspect, 1.0));
  float touchOrb = exp(-md * 5.5) * uPressed * 1.3;
  col += vec3(1.0, 1.0, 0.95) * touchOrb;

  // Tonemap
  col = col / (1.0 + col);
  col = pow(col, vec3(0.85));

  gl_FragColor = vec4(col, 1.0);
}
