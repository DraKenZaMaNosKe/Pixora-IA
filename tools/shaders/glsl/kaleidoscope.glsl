precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i),
        b = hash(i + vec2(1.0, 0.0)),
        c = hash(i + vec2(0.0, 1.0)),
        d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;
  float t = mod(uTime, 60.0);

  vec2 mouseUv = (uMouse * uResolution.xy - 0.5 * uResolution.xy) / uResolution.y;
  vec2 center = mix(vec2(0.0), mouseUv * 0.5, uPressed);
  uv -= center;

  float r = length(uv);
  float a = atan(uv.y, uv.x);

  float seg = 6.2831853 / 6.0;
  a = mod(a, seg);
  a = abs(a - seg * 0.5);

  float rotSpeed = 0.4 + uPressed * 1.5;
  a += mod(t * rotSpeed * 0.3, 6.2831853);

  vec2 sampUV = vec2(cos(a), sin(a)) * r * 4.0;
  vec2 p = sampUV + vec2(t * 0.3, t * 0.2);
  float n1 = noise(p);
  float n2 = noise(p * 2.0 + 1.0);
  float n3 = noise(p * 4.0 - 2.0);
  float pat = n1 * 0.5 + n2 * 0.3 + n3 * 0.2;

  float hue = mod(t * 0.15 + pat * 2.0, 1.0);
  vec3 col = 0.5 + 0.5 * cos(6.2831853 * (hue + vec3(0.0, 0.33, 0.67)));
  col *= smoothstep(0.0, 0.2, pat) * 1.1;
  col *= smoothstep(1.2, 0.2, r);

  gl_FragColor = vec4(col, 1.0);
}
