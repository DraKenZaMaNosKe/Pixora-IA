precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main(){
  vec2 uv = gl_FragCoord.xy / uResolution.xy;
  float t = mod(uTime, 60.0);
  float ar = uResolution.x / uResolution.y;

  vec2 grid = vec2(uv.x * ar, uv.y) * 12.0;
  vec2 id = floor(grid);
  vec2 f = fract(grid);

  float dir = step(0.5, hash(id));  // 0 horizontal, 1 vertical
  float lineDist = dir > 0.5 ? abs(f.x - 0.5) : abs(f.y - 0.5);
  float line = smoothstep(0.07, 0.05, lineDist);

  float junctionDist = max(abs(f.x - 0.5), abs(f.y - 0.5));
  float junction = smoothstep(0.10, 0.08, junctionDist) - smoothstep(0.08, 0.06, junctionDist);

  float nodeMask = step(0.8, hash(id + 5.0));
  float node = nodeMask * smoothstep(0.18, 0.12, length(f - 0.5));

  float pulsePos = dir > 0.5 ? f.x : f.y;
  float pulseT = mod(t * 0.7 + hash(id) * 3.0, 1.0);
  float pulseGlow = exp(-abs(pulsePos - pulseT) * 12.0) * line;

  vec2 mouseUv = uMouse;
  float md = length((uv - mouseUv) * vec2(ar, 1.0));
  float touchPulseR = mod(uTime * 0.8, 1.5) * uPressed;
  float touchPulse = exp(-abs(md - touchPulseR) * 18.0) * uPressed * line;

  vec3 cyan = vec3(0.0, 0.95, 1.0);
  vec3 blue = vec3(0.2, 0.4, 1.0);
  vec3 col = vec3(0.005, 0.01, 0.02);
  col += cyan * line * 0.25;
  col += blue * junction * 1.2;
  col += cyan * node * 1.0;
  col += vec3(0.5, 1.0, 1.0) * pulseGlow * 1.5;
  col += vec3(1.0, 0.95, 0.6) * touchPulse * 2.0;

  gl_FragColor = vec4(col, 1.0);
}
