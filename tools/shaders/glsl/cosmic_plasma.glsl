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

  // Slow drifting center (sin/cos args wrapped to [0, 2π))
  vec2 center = vec2(sin(mod(t*0.12, 6.2831853))*0.10,
                     cos(mod(t*0.15, 6.2831853))*0.08);
  vec2 p = (uv - center)*vec2(aspect, 1.0);

  // Organic distortion via fBm
  float distortion = (fbm(p*2.5 + vec2(t*0.15, 0.0)) - 0.5) * 0.30;
  float dist = length(p) + distortion;

  // One big metaball
  float field = smoothstep(0.50, 0.0, dist);

  // Internal currents (higher freq noise)
  float internal = fbm(p*7.0 + vec2(t*0.25, -t*0.20)) * field;

  // Purple→pink color cycle
  float hue = 0.5 + 0.5*sin(mod(t*0.18, 6.2831853));
  vec3 c = mix(vec3(0.6, 0.1, 0.8), vec3(1.0, 0.3, 0.7), hue);

  vec3 col = vec3(0.02, 0.01, 0.04);
  col += c * field * 0.85;
  col += vec3(1.0, 0.8, 1.0) * internal * field * 0.5;

  // Touch ripple at finger
  vec2 mp = (uMouse*uResolution.xy - 0.5*uResolution.xy)/uResolution.y;
  float md = length((uv-mp)*vec2(aspect, 1.0));
  col += c * exp(-md*4.5) * uPressed * 0.7;

  // Tonemap
  col = col / (1.0 + col*0.7);
  gl_FragColor = vec4(col, 1.0);
}
