precision highp float;

uniform float uTime;
uniform vec2 uResolution;

void main() {
    // Normalized coordinates (0.0 to 1.0)
    vec2 uv = gl_FragCoord.xy / uResolution.xy;

    // Visual grid to confirm coordinate mapping
    // Each cell is 1/10 of the screen
    vec2 grid = fract(uv * 10.0);
    float gridLine = step(0.95, grid.x) + step(0.95, grid.y);

    // Gradient: red = X axis (left to right), green = Y axis (bottom to top)
    vec3 color = vec3(uv.x, uv.y, 0.3);

    // Center crosshair
    float centerX = step(0.498, uv.x) * step(uv.x, 0.502);
    float centerY = step(0.498, uv.y) * step(uv.y, 0.502);
    float cross = max(centerX, centerY);

    // Border outline (1px)
    float border = 0.0;
    if (uv.x < 0.003 || uv.x > 0.997 || uv.y < 0.002 || uv.y > 0.998) {
        border = 1.0;
    }

    // Animated pulse to confirm time is working
    float pulse = sin(mod(uTime, 600.0) * 3.0) * 0.5 + 0.5;

    // Circle at center to confirm aspect ratio
    float aspect = uResolution.x / uResolution.y;
    vec2 centered = (uv - 0.5) * vec2(aspect, 1.0);
    float circle = smoothstep(0.21, 0.20, length(centered));
    float circleRing = smoothstep(0.22, 0.21, length(centered)) - circle;

    // Compose
    color += gridLine * 0.3;
    color = mix(color, vec3(1.0, 1.0, 0.0), cross * 0.8);
    color = mix(color, vec3(1.0), border);
    color = mix(color, vec3(0.0, pulse, 1.0), circle * 0.3);
    color = mix(color, vec3(1.0), circleRing);

    gl_FragColor = vec4(color, 1.0);
}
