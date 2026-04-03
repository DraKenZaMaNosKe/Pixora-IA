precision mediump float;

uniform float uTime;
uniform vec2 uResolution;

float hash(float n) { return fract(sin(n) * 43758.5453); }

float char(vec2 p, float t) {
    // Pseudo-character: random block pattern
    float h = hash(floor(p.x * 2.0) + floor(p.y * 2.0) * 100.0 + floor(t * 4.0));
    return step(0.5, h);
}

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution.xy;
    float t = mod(uTime, 600.0);

    vec3 col = vec3(0.0);
    float columns = 40.0;

    for (int layer = 0; layer < 3; layer++) {
        float depth = 1.0 - float(layer) * 0.3;
        float speed = 0.5 + float(layer) * 0.3;
        float colScale = columns * depth;

        vec2 grid = vec2(uv.x * colScale, uv.y * colScale * 2.0);
        float colIdx = floor(grid.x);

        // Each column has random speed and offset
        float colHash = hash(colIdx + float(layer) * 100.0);
        float fallSpeed = (0.5 + colHash * 1.5) * speed;
        float offset = colHash * 100.0;

        // Falling position
        float fall = fract(t * fallSpeed * 0.3 + offset);
        float yPos = fract(grid.y * 0.05 - fall);

        // Trail: bright at head, fading behind
        float headDist = yPos;
        float trail = smoothstep(0.6, 0.0, headDist) * depth;

        // Character brightness
        float charBright = char(grid, t * speed + offset);
        float brightness = trail * charBright;

        // Head glow (white-green)
        float head = smoothstep(0.03, 0.0, headDist) * depth;

        // Green with white head
        vec3 green = vec3(0.1, 0.9, 0.2) * brightness;
        vec3 white = vec3(0.7, 1.0, 0.7) * head;

        col += green + white;
    }

    // Subtle scanlines
    float scanline = sin(gl_FragCoord.y * 1.5) * 0.03;
    col -= scanline;

    // Vignette
    float vig = 1.0 - length((uv - 0.5) * 1.3) * 0.5;
    col *= vig;

    gl_FragColor = vec4(col, 1.0);
}
