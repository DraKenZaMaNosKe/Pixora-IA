// volcano_dragon.glsl — Pixora Volcano Dragon live wallpaper shader
// Ported from the WebGL preview in docs/design/deck_final_combined.html
//
// Effects applied on top of the background texture:
//   - Heat distortion near the volcano summit (pixel displacement via FBM noise)
//   - Procedural embers as glow points (16 points orbit + rise pattern)
//   - Summit pulse (eruption breathing glow)
//
// Uniforms expected (auto-set by GLShaderRenderer):
//   uTime       — float, seconds wrapped to [0, 600)
//   uResolution — vec2, surface size in px
//   uTex        — sampler2D, the wallpaper background image (NEW — requires GLShaderRenderer extension)
//
// Coordinate convention: gl_FragCoord.xy / uResolution gives 0..1 with origin
// at bottom-left (GLSL default). We flip Y when sampling the texture so it
// matches the image's top-left orientation.

precision mediump float;

uniform float uTime;
uniform vec2  uResolution;
uniform sampler2D uTex;

// ───────── noise helpers ─────────

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),                hash(i + vec2(1.0, 0.0)), u.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution;
    // Sample the texture with Y flipped so image top-left = uv (0, 1)
    vec2 texUv = vec2(uv.x, 1.0 - uv.y);

    // ───────── heat distortion ─────────
    // Heat mask: stronger near the volcano summit (top center of the bg image)
    // Convert to "image space" where y=0 is top of image, y=1 is bottom
    float imgY = 1.0 - uv.y;
    float heat = smoothstep(0.35, 0.6, 1.0 - imgY)
               * smoothstep(0.1, 0.5, 1.0 - abs(0.5 - uv.x) * 2.0);
    float dist = noise(vec2(uv.x * 10.0, imgY * 20.0 - uTime * 2.0)) * 0.014 * heat;
    vec2 distortedUv = texUv + vec2(dist, 0.0);

    // Sample the background with heat-distorted UVs
    vec4 col = texture2D(uTex, distortedUv);

    // ───────── procedural embers (16 points) ─────────
    for (int i = 0; i < 16; i++) {
        float fi = float(i);
        // Each ember has a unique x position oscillating around 0.5
        // and a y that rises from ~0.55 to ~0.0 (bottom toward top in image space)
        vec2 ep = vec2(
            0.5 + sin(fi * 1.3 + uTime * 0.3) * 0.12,
            0.45 - mod(uTime * 0.25 + fi * 0.11, 1.0) * 0.55
        );
        // Distance from current pixel to ember center
        // (compute in image-y space so embers feel anchored to scene)
        vec2 pixelImg = vec2(uv.x, imgY);
        float d = distance(pixelImg, ep);

        // Soft glow falloff with twinkling brightness
        float ember = 0.008 / (d + 0.002);
        ember *= smoothstep(0.45, 0.0, d) * (0.3 + sin(uTime * 5.0 + fi) * 0.2);

        col.rgb += vec3(1.0, 0.55, 0.15) * ember * 0.85;
    }

    // ───────── summit pulse (eruption glow) ─────────
    float summitDist = distance(vec2(uv.x, imgY), vec2(0.5, 0.45));
    float glow = 0.05 / (summitDist + 0.04);
    glow *= 0.55 + 0.3 * sin(uTime * 1.5);
    col.rgb += vec3(1.0, 0.5, 0.15) * glow * 0.30;

    gl_FragColor = col;
}
