precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;
  float t = mod(uTime, 60.0);

  vec2 grid = uv * 5.0;
  vec2 cellId = floor(vec2(grid.x + grid.y * 0.5, grid.y));
  vec2 cellUV = vec2(fract(grid.x + grid.y * 0.5), fract(grid.y));
  bool upper = cellUV.x + cellUV.y > 1.0;
  vec2 triId = cellId + (upper ? vec2(1.0, 0.5) : vec2(0.0, 0.0));

  float edge = upper ? (1.0 - cellUV.x - cellUV.y) : min(cellUV.x, cellUV.y);
  float fill = smoothstep(0.02, 0.10, edge);

  float h1 = hash(triId);
  float h2 = hash(triId + 17.0);
  vec3 paletteA = vec3(1.0, 0.0, 0.8);
  vec3 paletteB = vec3(0.0, 1.0, 0.9);
  vec3 paletteC = vec3(0.6, 0.2, 1.0);
  vec3 paletteD = vec3(0.3, 1.0, 0.5);
  vec3 base = h1 < 0.25 ? paletteA :
              h1 < 0.50 ? paletteB :
              h1 < 0.75 ? paletteC : paletteD;

  float breatheArg = mod(t * 0.8 + h2 * 6.2831853, 6.2831853);
  float breathe = 0.4 + 0.6 * (0.5 + 0.5 * sin(breatheArg));

  vec2 mouseUv = (uMouse * uResolution.xy - 0.5 * uResolution.xy) / uResolution.y;
  float md = length(uv - mouseUv);
  float ripple = exp(-md * 2.5) * uPressed * (0.7 + 0.3 * sin(md * 18.0 - t * 6.0));

  vec3 col = base * breathe * fill * 0.8;
  col += base * 0.2 * (1.0 - fill);
  col += vec3(1.0, 1.0, 1.0) * ripple * fill;
  col *= 0.9;

  gl_FragColor = vec4(col, 1.0);
}
