precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){
  vec2 i = floor(p), f = fract(p);
  f = f*f*(3.0 - 2.0*f);
  return mix(mix(hash(i),               hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p){
  float v = 0.0; float a = 0.5;
  for (int i = 0; i < 4; i++){ v += a*noise(p); p *= 2.0; a *= 0.5; }
  return v;
}

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5*uResolution.xy)/uResolution.y;
  float t = mod(uTime, 60.0);
  float aspect = uResolution.x/uResolution.y;
  vec2 p = uv * vec2(aspect, 1.0);

  // Spiral warp — touch boosts swirl speed
  float r = length(p);
  float ang = atan(p.y, p.x);
  float swirl = 0.3 + uPressed * 0.4;
  ang += r * 5.0 + mod(t*0.4, 6.2831853) * swirl;
  vec2 swirled = vec2(cos(ang), sin(ang)) * r;

  // Noise-distorted distance from center
  float distortion = (fbm(swirled*4.0 + vec2(t*0.15, 0.0)) - 0.5) * 0.20;
  float dist = r + distortion;
  float field = smoothstep(0.55, 0.0, dist);

  // Spiral arms via noise on swirled coords
  float arms = fbm(swirled*6.0) * field;

  // Galaxy palette: bright cream core → pink mid → deep purple edge
  vec3 core = vec3(0.95, 0.85, 0.6);
  vec3 mid = vec3(0.7, 0.3, 0.9);
  vec3 edge = vec3(0.4, 0.1, 0.6);
  vec3 c = mix(core, mid, smoothstep(0.0, 0.2, r));
  c = mix(c, edge, smoothstep(0.2, 0.5, r));

  vec3 col = vec3(0.005, 0.005, 0.015);
  col += c * field;
  col += vec3(1.0, 0.85, 1.0) * pow(arms, 2.0) * field * 0.7;

  col = col / (1.0 + col*0.5);
  gl_FragColor = vec4(col, 1.0);
}
