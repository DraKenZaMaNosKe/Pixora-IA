precision mediump float;

uniform float uTime;
uniform vec2 uResolution;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i), hash(i + vec2(1,0)), f.x),
        mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x),
        f.y
    );
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 6; i++) {
        v += a * noise(p);
        p = p * 2.1 + vec2(100.0);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution.xy;
    float t = mod(uTime, 600.0) * 0.05;

    // Warped coordinates for cosmic swirl
    vec2 q = vec2(fbm(uv * 2.0 + t * 0.3), fbm(uv * 2.0 + vec2(1.7, 9.2) + t * 0.2));
    vec2 r = vec2(fbm(uv * 3.0 + q + t * 0.1), fbm(uv * 3.0 + vec2(8.3, 2.8) + t * 0.15));

    float f = fbm(uv * 2.0 + r);

    // Nebula colors: deep purple, hot pink, cyan, gold
    vec3 col = mix(vec3(0.05, 0.0, 0.1), vec3(0.6, 0.0, 0.4), f);
    col = mix(col, vec3(0.0, 0.5, 0.8), q.x * 0.8);
    col = mix(col, vec3(1.0, 0.6, 0.1), r.y * r.y * 0.5);
    col = mix(col, vec3(0.9, 0.1, 0.5), smoothstep(0.4, 0.8, f) * 0.4);

    // Stars
    float stars = 0.0;
    for (int i = 0; i < 3; i++) {
        vec2 sUV = uv * (300.0 + float(i) * 200.0);
        float s = hash(floor(sUV));
        s = step(0.998, s);
        float tw = sin(s * 999.0 + mod(uTime, 600.0) * 3.0 + float(i)) * 0.5 + 0.5;
        stars += s * tw;
    }
    col += stars * 0.8;

    // Brightness boost center
    float glow = exp(-length(uv - 0.5) * 2.5) * 0.3;
    col += glow * vec3(0.4, 0.2, 0.6);

    gl_FragColor = vec4(col, 1.0);
}
