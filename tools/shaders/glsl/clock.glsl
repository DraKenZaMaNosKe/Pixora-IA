precision highp float;
uniform float uTime;
uniform vec2  uResolution;
uniform vec2  uMouse;
uniform float uPressed;
uniform float uClockSec;   // seconds since midnight, 0..86400, fractional

vec2 rot2(vec2 p, float a){ float c = cos(a), s = sin(a); return mat2(c, -s, s, c) * p; }

// Distance to vertical segment (0,0)->(0,len), rotated by ang (0 = points up).
float handDist(vec2 p, float ang, float len){
  vec2 rp = rot2(p, -ang);
  float ly = clamp(rp.y, 0.0, len);
  return length(vec2(rp.x, rp.y - ly));
}

void main(){
  // Normalize so uv.x AND uv.y span the SHORT dimension equally — clock face
  // sized 0..0.42 fits comfortably on both portrait and landscape screens.
  float minDim = min(uResolution.x, uResolution.y);
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / minDim;
  float t = mod(uTime, 60.0);

  float sec   = mod(uClockSec, 60.0);
  float minF  = mod(uClockSec, 3600.0) / 60.0;
  float hourF = mod(uClockSec, 43200.0) / 3600.0;
  float angSec  = sec  / 60.0 * 6.2831853;
  float angMin  = minF / 60.0 * 6.2831853;
  float angHour = hourF / 12.0 * 6.2831853;

  float r = length(uv);
  float faceR = 0.42;

  // ── deep blue gradient background ──
  vec3 col = mix(vec3(0.04, 0.05, 0.12), vec3(0.01, 0.01, 0.04), r * 1.2);

  // ── outer glow halo around the face ──
  float halo = exp(-(r - faceR) * 8.0) * step(r, faceR + 0.15);
  col += vec3(0.30, 0.50, 0.95) * halo * 0.25;

  // ── dial face (dark glass) ──
  float face = smoothstep(faceR, faceR - 0.005, r);
  col = mix(col, vec3(0.05, 0.07, 0.14), face * 0.90);
  // inner subtle radial gradient on face
  col -= vec3(0.0, 0.0, 0.03) * face * (1.0 - r / faceR) * 0.3;

  // ── metallic outer rim ──
  float rim = smoothstep(0.006, 0.0, abs(r - faceR));
  col += vec3(0.75, 0.85, 1.0) * rim * 1.0;
  // inner accent ring
  float rimAcc = smoothstep(0.003, 0.0, abs(r - (faceR - 0.014)));
  col += vec3(0.20, 0.35, 0.60) * rimAcc * 0.9;

  // ── tick marks ──
  // Polar angle: 0 = up, clockwise positive.
  float pa = atan(uv.x, uv.y);
  if (pa < 0.0) pa += 6.2831853;

  // 60 minute ticks (small)
  float t60 = mod(pa * 60.0 / 6.2831853, 1.0);
  float minTick = min(t60, 1.0 - t60);
  float mt = smoothstep(0.10, 0.0, minTick)
           * smoothstep(faceR - 0.010, faceR - 0.025, r)
           * step(faceR - 0.030, r);
  col += vec3(0.55, 0.70, 0.90) * mt * 0.55;

  // 12 hour ticks (large)
  float t12 = mod(pa * 12.0 / 6.2831853, 1.0);
  float hTick = min(t12, 1.0 - t12);
  float ht = smoothstep(0.12, 0.0, hTick)
           * smoothstep(faceR - 0.005, faceR - 0.055, r)
           * step(faceR - 0.065, r);
  col += vec3(0.95, 0.98, 1.0) * ht * 1.2;

  // 4 cardinal ticks (12/3/6/9) — thicker
  float t4 = mod(pa * 4.0 / 6.2831853, 1.0);
  float cTick = min(t4, 1.0 - t4);
  float ct = smoothstep(0.06, 0.0, cTick)
           * smoothstep(faceR - 0.005, faceR - 0.075, r)
           * step(faceR - 0.085, r);
  col += vec3(1.0, 1.0, 1.0) * ct * 0.6;

  // ── hands ──
  // Hour hand: thick, short
  float hourD = handDist(uv, angHour, 0.20);
  col = mix(col, vec3(0.92, 0.96, 1.0), smoothstep(0.013, 0.009, hourD));

  // Minute hand: medium, longer
  float minD = handDist(uv, angMin, 0.30);
  col = mix(col, vec3(1.0, 1.0, 1.0), smoothstep(0.009, 0.005, minD));

  // Second hand: thin, longest, gradient color
  float secD = handDist(uv, angSec, 0.35);
  vec3 secColor = mix(vec3(1.0, 0.35, 0.50),
                      vec3(0.30, 0.95, 1.0),
                      0.5 + 0.5 * sin(mod(t * 0.6, 6.2831853)));
  col = mix(col, secColor, smoothstep(0.0045, 0.0025, secD));
  // counterweight tail
  float secTail = handDist(uv, angSec + 3.1415926, 0.07);
  col = mix(col, secColor, smoothstep(0.006, 0.004, secTail));

  // ── center hub ──
  col = mix(col, vec3(0.90, 0.95, 1.0), smoothstep(0.024, 0.020, r));
  col = mix(col, secColor * 0.9, smoothstep(0.011, 0.008, r));

  // ── hour-change glow pulse (first 2 seconds after the hour) ──
  float justChanged = smoothstep(120.0, 0.0, minF * 60.0 + sec); // minF*60 + sec is "seconds into hour"
  // We want: bright right at top of the hour, fade over 120 sec
  float secOfHour = minF * 60.0 + sec;
  float pulse = smoothstep(120.0, 0.0, secOfHour) * smoothstep(0.6, 0.0, r) * 0.5;
  col += vec3(0.6, 0.8, 1.0) * pulse;

  // ── touch halo ──
  vec2 mU = (uMouse * uResolution.xy - 0.5 * uResolution.xy) / minDim;
  float md = length(uv - mU);
  col += vec3(0.95, 0.85, 1.0) * exp(-md * 5.0) * uPressed * 1.4;

  // outer vignette
  col *= smoothstep(1.0, 0.15, r);

  gl_FragColor = vec4(col, 1.0);
}
