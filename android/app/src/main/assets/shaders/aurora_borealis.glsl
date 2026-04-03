precision mediump float;

uniform float uTime;
uniform vec2 uResolution;

// Safe periodic noise (no large float accumulation)
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution.xy;

    // Time: use fract and mod to keep values small
    float t = mod(uTime, 600.0);
    float slowT = t * 0.1;

    // Aurora vertical position (upper portion of screen)
    float auroraY = uv.y * 2.0 - 0.3;

    // Flowing noise layers
    float n1 = fbm(vec2(uv.x * 3.0 + slowT * 0.5, auroraY * 1.5 + slowT * 0.2));
    float n2 = fbm(vec2(uv.x * 5.0 - slowT * 0.3, auroraY * 2.0 + slowT * 0.15));
    float n3 = fbm(vec2(uv.x * 2.0 + slowT * 0.7, auroraY * 0.8 - slowT * 0.1));

    // Aurora shape: concentrated in upper half, flowing
    float aurora = smoothstep(0.3, 0.7, n1) * smoothstep(0.0, 0.5, uv.y) * smoothstep(1.0, 0.4, uv.y);
    float aurora2 = smoothstep(0.4, 0.8, n2) * smoothstep(0.1, 0.6, uv.y) * smoothstep(0.95, 0.35, uv.y);
    float aurora3 = smoothstep(0.35, 0.75, n3) * smoothstep(0.05, 0.55, uv.y) * smoothstep(1.0, 0.45, uv.y);

    // Colors: green, cyan, purple, pink (classic aurora)
    vec3 col1 = vec3(0.1, 0.9, 0.3) * aurora * 1.2;        // Green
    vec3 col2 = vec3(0.1, 0.6, 0.9) * aurora2 * 0.8;       // Cyan
    vec3 col3 = vec3(0.6, 0.1, 0.8) * aurora3 * 0.6;       // Purple

    // Combine aurora layers
    vec3 auroraColor = col1 + col2 + col3;

    // Stars
    float stars = 0.0;
    for (int i = 0; i < 3; i++) {
        vec2 starUV = uv * (200.0 + float(i) * 150.0);
        float star = hash(floor(starUV));
        star = step(0.997, star) * star;
        // Twinkling
        float twinkle = sin(star * 1000.0 + t * 2.0 + float(i)) * 0.5 + 0.5;
        stars += star * twinkle * smoothstep(0.0, 0.3, uv.y);
    }

    // Dark sky gradient (dark blue at top to black at bottom)
    vec3 sky = mix(
        vec3(0.0, 0.0, 0.02),           // Near black at bottom
        vec3(0.02, 0.02, 0.08),          // Very dark blue at top
        uv.y
    );

    // Ground: dark silhouette with subtle terrain
    float terrain = noise(vec2(uv.x * 8.0, 0.0)) * 0.08;
    float ground = smoothstep(terrain + 0.05, terrain, uv.y);
    vec3 groundColor = vec3(0.01, 0.01, 0.02);

    // Final composite
    vec3 color = sky + auroraColor + stars;
    color = mix(color, groundColor, ground);

    // Subtle vignette
    float vignette = 1.0 - length((uv - 0.5) * vec2(1.0, 0.6)) * 0.8;
    color *= vignette;

    gl_FragColor = vec4(color, 1.0);
}
