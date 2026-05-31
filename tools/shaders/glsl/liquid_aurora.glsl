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

  vec2 mp = (uMouse*uResolution.xy - 0.5*uResolution.xy)/uResolution.y;
  // Base center + pull toward touch when pressed
  vec2 baseCenter = vec2(sin(mod(t*0.08, 6.2831853))*0.05,
                         cos(mod(t*0.10, 6.2831853))*0.05);
  vec2 center = mix(baseCenter, mp, uPressed * 0.6);
  vec2 p = (uv - center)*vec2(aspect, 1.0);

  float distortion = (fbm(p*3.0 + vec2(-t*0.12, t*0.18)) - 0.5) * 0.35;
  float dist = length(p) + distortion;
  float field = smoothstep(0.55, 0.0, dist);
  float internal = fbm(p*6.0 + vec2(t*0.30, t*0.10)) * field;

  // Green → cyan → blue aurora palette
  vec3 c1 = vec3(0.1, 1.0, 0.4);
  vec3 c2 = vec3(0.0, 0.8, 1.0);
  vec3 c3 = vec3(0.3, 0.6, 1.0);
  float hue = 0.5 + 0.5*sin(mod(t*0.15, 6.2831853));
  vec3 c = mix(c1, c2, hue);
  c = mix(c, c3, internal * 0.5);

  vec3 col = vec3(0.005, 0.02, 0.03);
  col += c * field * 0.9;
  col += vec3(0.8, 1.0, 0.9) * pow(internal, 2.0) * field * 0.6;

  col = col / (1.0 + col*0.7);
  gl_FragColor = vec4(col, 1.0);
}
