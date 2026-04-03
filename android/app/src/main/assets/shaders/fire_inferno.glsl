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
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.0 + vec2(100.0);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution.xy;
    float t = mod(uTime, 600.0);

    // Fire rises upward — offset Y with time
    vec2 fireUV = vec2(uv.x * 3.0, uv.y * 4.0 - t * 1.5);

    // Multiple noise layers for turbulence
    float n1 = fbm(fireUV);
    float n2 = fbm(fireUV * 2.0 + vec2(t * 0.3, 0.0));
    float n3 = fbm(vec2(uv.x * 6.0 + t * 0.1, uv.y * 8.0 - t * 2.0));

    // Fire shape: stronger at bottom, fades at top
    float fireShape = (1.0 - uv.y);
    fireShape = pow(fireShape, 1.5);

    // Combine noise with shape
    float fire = fireShape * (n1 * 0.5 + n2 * 0.3 + n3 * 0.2);
    fire = smoothstep(0.1, 0.8, fire);

    // Fire color gradient: white core → yellow → orange → red → dark
    vec3 col;
    if (fire > 0.8) {
        col = mix(vec3(1.0, 0.9, 0.5), vec3(1.0, 1.0, 0.9), (fire - 0.8) * 5.0);
    } else if (fire > 0.5) {
        col = mix(vec3(1.0, 0.5, 0.0), vec3(1.0, 0.9, 0.5), (fire - 0.5) * 3.33);
    } else if (fire > 0.2) {
        col = mix(vec3(0.8, 0.1, 0.0), vec3(1.0, 0.5, 0.0), (fire - 0.2) * 3.33);
    } else {
        col = mix(vec3(0.1, 0.0, 0.0), vec3(0.8, 0.1, 0.0), fire * 5.0);
    }

    // Embers / sparks
    float sparks = 0.0;
    for (int i = 0; i < 2; i++) {
        vec2 sparkUV = uv * vec2(20.0, 30.0);
        float sparkHash = hash(floor(sparkUV) + float(i) * 50.0);
        float sparkY = fract(sparkHash * 10.0 - t * (0.5 + sparkHash));
        float sparkBright = step(0.98, sparkHash) * smoothstep(0.0, 0.1, sparkY) * smoothstep(1.0, 0.5, sparkY);
        sparks += sparkBright;
    }
    col += sparks * vec3(1.0, 0.6, 0.1);

    // Dark background
    vec3 bg = vec3(0.02, 0.0, 0.0);
    col = mix(bg, col, fire + sparks * 0.3);

    // Subtle glow at bottom
    col += vec3(0.15, 0.03, 0.0) * (1.0 - uv.y) * 0.5;

    gl_FragColor = vec4(col, 1.0);
}
