precision mediump float;

uniform float uTime;
uniform vec2 uResolution;

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution.xy;
    float t = mod(uTime, 600.0);

    // Perspective transform: bottom wider, top narrower (road effect)
    float perspective = 1.0 / (uv.y * 3.0 + 0.3);
    vec2 gridUV = vec2((uv.x - 0.5) * perspective * 5.0, perspective * 3.0 - t * 0.8);

    // Grid lines
    vec2 grid = abs(fract(gridUV) - 0.5);
    float lineX = smoothstep(0.02, 0.0, grid.x);
    float lineY = smoothstep(0.02, 0.0, grid.y);
    float gridLine = max(lineX, lineY);

    // Fade grid with distance (top = further)
    gridLine *= smoothstep(1.0, 0.3, uv.y);
    gridLine *= (1.0 - uv.y);

    // Grid color: neon cyan/magenta
    float colorPulse = sin(t * 2.0) * 0.5 + 0.5;
    vec3 gridColor = mix(
        vec3(0.0, 0.8, 1.0),    // Cyan
        vec3(1.0, 0.0, 0.8),    // Magenta
        colorPulse * 0.3 + uv.x * 0.4
    );

    // Sun
    vec2 sunCenter = vec2(0.5, 0.45);
    float sunDist = length(uv - sunCenter);
    float sun = smoothstep(0.15, 0.14, sunDist);

    // Sun horizontal lines (retro effect)
    float sunLines = step(0.5, fract(uv.y * 30.0));
    sun *= mix(1.0, sunLines, smoothstep(0.45, 0.35, uv.y));

    // Sun color gradient
    vec3 sunColor = mix(vec3(1.0, 0.8, 0.0), vec3(1.0, 0.2, 0.4), smoothstep(0.45, 0.35, uv.y));

    // Sun glow
    float sunGlow = exp(-sunDist * 4.0) * 0.5;
    vec3 glowColor = vec3(1.0, 0.3, 0.5) * sunGlow;

    // Sky gradient
    vec3 sky = mix(
        vec3(0.0, 0.0, 0.05),    // Dark at bottom
        vec3(0.1, 0.0, 0.2),     // Purple at horizon
        smoothstep(0.0, 0.5, uv.y)
    );
    sky = mix(sky, vec3(0.0, 0.0, 0.1), smoothstep(0.5, 1.0, uv.y));

    // Stars (only in upper sky)
    float stars = 0.0;
    vec2 starUV = uv * 300.0;
    float starHash = fract(sin(dot(floor(starUV), vec2(127.1, 311.7))) * 43758.5453);
    stars = step(0.998, starHash) * smoothstep(0.5, 0.8, uv.y);
    float twinkle = sin(starHash * 1000.0 + t * 3.0) * 0.5 + 0.5;
    stars *= twinkle;

    // Compose
    vec3 col = sky;
    col += stars;
    col = mix(col, sunColor, sun);
    col += glowColor;

    // Ground (grid area below horizon)
    if (uv.y < 0.5) {
        vec3 ground = vec3(0.0, 0.0, 0.03);
        ground += gridColor * gridLine;
        // Horizon glow
        ground += vec3(0.3, 0.0, 0.3) * exp(-(0.5 - uv.y) * 8.0);
        col = ground;
    }

    // Mountains/terrain silhouette at horizon
    float terrainX = uv.x * 8.0;
    float terrain = sin(terrainX) * 0.02 + sin(terrainX * 2.3) * 0.015 + sin(terrainX * 5.7) * 0.008;
    float terrainMask = smoothstep(0.5 + terrain, 0.5 + terrain + 0.005, uv.y);
    col *= terrainMask + (1.0 - terrainMask) * 0.05;

    gl_FragColor = vec4(col, 1.0);
}
