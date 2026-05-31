precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;

void main(){
  vec2 uv = gl_FragCoord.xy / uResolution.xy;
  float t = mod(uTime, 60.0);

  vec3 col;
  float horizon = 0.5;

  if (uv.y > horizon){
    // Sky with sun
    vec3 skyTop = vec3(0.04, 0.02, 0.12);
    vec3 skyMid = vec3(0.45, 0.10, 0.50);
    float skyT = (uv.y - horizon) / (1.0 - horizon);
    col = mix(skyMid, skyTop, skyT);

    vec2 sunC = vec2(0.5, horizon + 0.15);
    float sd = length((uv - sunC) * vec2(1.0, 1.4));
    float sun = smoothstep(0.20, 0.18, sd);
    float bars = step(0.5, fract((uv.y - sunC.y) * 20.0 - 0.5));
    float sunMask = max(0.0, sun - bars * smoothstep(sunC.y - 0.0, sunC.y + 0.12, uv.y));
    vec3 sunCol = mix(vec3(1.0, 0.85, 0.25), vec3(1.0, 0.25, 0.55), (uv.y - sunC.y) * 3.0 + 0.5);
    col = mix(col, sunCol, sunMask);
    col += vec3(1.0, 0.45, 0.55) * smoothstep(0.45, 0.0, sd) * 0.4;
  } else {
    // Perspective floor grid
    float fp = (horizon - uv.y) / horizon;
    float depth = 1.0 / max(fp, 0.01);
    float z = depth * 0.15 + t * 0.6;
    float gx = abs(fract((uv.x - 0.5) * depth * 2.0) - 0.5);
    float gz = abs(fract(z) - 0.5);
    float lineX = smoothstep(0.05, 0.0, gx) * smoothstep(1.0, 0.3, fp * 2.0);
    float lineZ = smoothstep(0.05, 0.0, gz);
    vec3 floorBase = mix(vec3(0.10, 0.04, 0.18), vec3(0.04, 0.02, 0.08), fp);
    vec3 gridCol = vec3(1.0, 0.30, 0.60);
    col = floorBase + gridCol * (lineX + lineZ) * 0.8;
  }

  // Lightning from touch (sky only)
  if (uPressed > 0.01 && uv.y > horizon){
    vec2 mouseUv = uMouse;
    float distToBolt = abs(uv.x - mouseUv.x - sin(mod(uv.y * 30.0 + t * 20.0, 6.2831853)) * 0.04);
    float bolt = exp(-distToBolt * 80.0) * uPressed * step(uv.y, mouseUv.y);
    col += vec3(0.6, 0.9, 1.0) * bolt * 2.0;
  }

  gl_FragColor = vec4(col, 1.0);
}
