precision highp float;

uniform float uTime;
uniform vec2 uResolution;

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution.xy;

    // Cuadro centrado, sin relleno, solo borde
    // Margen: 10% de cada lado
    float left   = 0.1;
    float right  = 0.9;
    float bottom = 0.1;
    float top    = 0.9;

    // Grosor del borde en UV (ajustado por aspect ratio en X)
    float thickness = 0.004;

    // Detectar si estamos en el borde del cuadro
    float border = 0.0;

    // Borde izquierdo
    if (uv.x > left - thickness && uv.x < left + thickness && uv.y > bottom && uv.y < top)
        border = 1.0;
    // Borde derecho
    if (uv.x > right - thickness && uv.x < right + thickness && uv.y > bottom && uv.y < top)
        border = 1.0;
    // Borde inferior
    if (uv.y > bottom - thickness && uv.y < bottom + thickness && uv.x > left && uv.x < right)
        border = 1.0;
    // Borde superior
    if (uv.y > top - thickness && uv.y < top + thickness && uv.x > left && uv.x < right)
        border = 1.0;

    // Fondo negro, borde blanco
    vec3 color = vec3(border);

    gl_FragColor = vec4(color, 1.0);
}
