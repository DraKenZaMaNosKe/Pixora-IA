precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;
  float t = mod(uTime, 60.0);

  vec2 b1 = vec2(0.30 * cos(mod(t * 0.5, 6.2831853)),
                 0.30 * sin(mod(t * 0.7, 6.2831853)));
  vec2 b2 = vec2(0.25 * cos(mod(t * -0.6 + 1.5, 6.2831853)),
                 0.25 * sin(mod(t * 0.45 + 1.5, 6.2831853)));
  vec2 b3 = vec2(0.20 * cos(mod(t * 0.4 + 3.0, 6.2831853)),
                 0.35 * sin(mod(t * -0.55 + 3.0, 6.2831853)));
  float r1 = 0.18, r2 = 0.16, r3 = 0.14;

  float f = (r1 * r1) / dot(uv - b1, uv - b1)
          + (r2 * r2) / dot(uv - b2, uv - b2)
          + (r3 * r3) / dot(uv - b3, uv - b3);

  vec2 mouseUv = (uMouse * uResolution.xy - 0.5 * uResolution.xy) / uResolution.y;
  float rT = 0.15;
  f += (rT * rT) / dot(uv - mouseUv, uv - mouseUv) * uPressed;

  float surface = smoothstep(0.8, 1.4, f);

  vec3 cA = vec3(0.10, 0.90, 1.0);
  vec3 cB = vec3(1.00, 0.20, 0.85);
  vec3 cC = vec3(0.50, 0.30, 1.0);
  vec3 col = mix(cA, cB, 0.5 + 0.5 * sin(mod(t * 0.4, 6.2831853)));
  col = mix(col, cC, 0.5 + 0.5 * sin(mod(t * 0.27 + 2.0, 6.2831853)));

  float halo = smoothstep(0.4, 1.0, f) * 0.4;
  vec3 final = vec3(0.02, 0.02, 0.06);
  final += col * surface * 1.1;
  final += col * halo * 0.5;

  gl_FragColor = vec4(final, 1.0);
}
