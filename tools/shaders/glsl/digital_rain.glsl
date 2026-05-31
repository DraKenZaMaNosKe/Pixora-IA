precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash11(float p){ return fract(sin(p * 78.233) * 43758.5453); }

void main(){
  vec2 uv = gl_FragCoord.xy / uResolution.xy;
  float t = mod(uTime, 60.0);

  float cols = 22.0;
  float colIdx = floor(uv.x * cols);
  float colSeed = hash11(colIdx * 7.13);
  float speed = 0.3 + colSeed * 0.8;
  float headY = 1.0 - mod(t * speed + colSeed * 2.0, 1.4);

  float rows = 36.0;
  float rowIdx = floor(uv.y * rows);
  float glyphSeed = hash(vec2(colIdx, rowIdx + floor(t * speed * rows * 0.5)));
  float glyph = step(0.55, glyphSeed);

  float dy = uv.y - headY;
  float trail = 0.0;
  if (dy < 0.0) trail = exp(dy * 4.5);
  float head = exp(-abs(dy) * 60.0) * 1.5;

  // Touch — red shift in columns near finger
  vec2 mouseUv = uMouse;
  float colDist = abs(uv.x - mouseUv.x);
  float touchInfluence = exp(-colDist * 15.0) * uPressed;

  vec3 green = vec3(0.15, 1.0, 0.45);
  vec3 red   = vec3(1.0, 0.15, 0.25);
  vec3 colChar = mix(green, red, touchInfluence);

  float bright = (trail + head) * glyph;
  vec3 col = vec3(0.0, 0.02, 0.01);
  col += colChar * bright;
  col += vec3(1.0) * head * glyph * 0.4;

  gl_FragColor = vec4(col, 1.0);
}
