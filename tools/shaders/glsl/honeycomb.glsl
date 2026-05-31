precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec2 hexCoord(vec2 p, out vec2 id){
  vec2 s = vec2(1.0, 1.7320508);
  vec4 hC = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
  vec4 h  = vec4(p - hC.xy * s, p - (hC.zw + 0.5) * s);
  vec4 winner = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hC.xy) : vec4(h.zw, hC.zw + 0.5);
  id = winner.zw;
  return winner.xy;
}

float hexDist(vec2 p){
  p = abs(p);
  return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;
  float t = mod(uTime, 60.0);

  vec2 id;
  vec2 hp = hexCoord(uv * 6.0, id);
  float edge = hexDist(hp);
  float cellGlow = smoothstep(0.50, 0.45, edge);
  float border = smoothstep(0.50, 0.49, edge) - smoothstep(0.47, 0.46, edge);

  float wave = sin(mod((id.x + id.y) * 0.6 - t * 1.8, 6.2831853));
  float pulse = smoothstep(0.4, 1.0, wave);

  vec3 cyan = vec3(0.0, 0.9, 1.0);
  vec3 violet = vec3(0.6, 0.2, 1.0);
  vec3 base = mix(violet, cyan, 0.5 + 0.5 * sin(mod(id.x * 0.3 + id.y * 0.5 + t * 0.3, 6.2831853)));

  // Touch
  vec2 mouseUv = (uMouse * uResolution.xy - 0.5 * uResolution.xy) / uResolution.y;
  float md = length(uv - mouseUv);
  float touchGlow = exp(-md * 4.5) * uPressed;

  vec3 col = vec3(0.02, 0.03, 0.08);
  col += base * cellGlow * 0.15;
  col += base * border * 0.6;
  col += base * pulse * 1.4 * cellGlow;
  col += vec3(1.0, 0.6, 1.0) * touchGlow * 1.8 * cellGlow;

  gl_FragColor = vec4(col, 1.0);
}
