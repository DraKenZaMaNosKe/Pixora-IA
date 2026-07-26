# Bone Rigging 2D para canvas_scene — Design Spec

**Fecha:** 2026-07-25
**Estado:** aprobado (diseño), pendiente implementación
**Alcance:** vertical slice — UN personaje (heroína candy-mecha), validable como live wallpaper en Samsung SM-A155M (RF8X903KZ3K).

## Objetivo

Animar un personaje ilustrado moviendo sus PARTES individualmente por código, unidas jerárquicamente por pivotes padre-hijo (mover el torso arrastra cabeza/brazos/piernas), sin MP4. Es la evolución del sistema de sprites de `canvas_scene`. Este slice valida la técnica; NO incluye editor visual, publicación, ni partes generadas por IA.

## Decisiones de arquitectura

### 1. Bloque `rig` nuevo y aislado (no sobre sprites ni image_layers)
- **Descartado extender SPRITES**: `SpriteController` es una sealed class de behaviors de posición independientes (orbit/wander/translate/static); agregarle `parent`+pivote configurable contamina la factory y arriesga el fast-path de `drawAt`.
- **Descartado extender IMAGE_LAYERS**: son fondos cover-fit **pre-escalados** (`ensureLayersPrescaled`, invariante de rendimiento); rotarlas/jerarquizarlas rompe eso.
- **Elegido: bloque `rig` nuevo** con `RigController.kt` aislado → **cero riesgo de regresión** en las escenas publicadas (no toca ningún camino de dibujo existente). Modelo limpio: rig = jerarquía + keyframes.
- **Reúso clave**: las partes se declaran en `sprites[]` con `behavior: "preload"` (ya existe: carga el `SpriteSheet` sin controller que dibuje). Así la descarga/decode/cache de bitmaps la hace la maquinaria de sprites existente → cero cambios en Dart. El rig referencia cada parte por `sprite: "<name>"` y toma el bitmap de `sheets[name]`.

### 2. Formato del spec (`rigs[]`, array desde el día 1 para no migrar)

```jsonc
{
  "id": "heroina_candy_mecha_rig_v1",
  "type": "canvas_scene",
  "image_layers": [
    { "key": "bg", "url": ".../fondo_limpio.webp", "z": 0, "parallax_factor": 0.05, "scroll_factor": 0.0 }
  ],
  "sprites": [
    { "name": "rig_torso",    "manifest_key": "rigs/heroina_v1/torso",    "behavior": "preload", "params": {"high_res": true} },
    { "name": "rig_head",     "manifest_key": "rigs/heroina_v1/head",     "behavior": "preload", "params": {"high_res": true} },
    { "name": "rig_arm",      "manifest_key": "rigs/heroina_v1/arm",      "behavior": "preload", "params": {"high_res": true} },
    { "name": "rig_leg_up",   "manifest_key": "rigs/heroina_v1/leg_up",   "behavior": "preload", "params": {"high_res": true} },
    { "name": "rig_leg_bent", "manifest_key": "rigs/heroina_v1/leg_bent", "behavior": "preload", "params": {"high_res": true} }
  ],
  "rigs": [{
    "name": "heroina",
    "z": 10,
    "anchor": [0.5, 0.55],       // pantalla (SPEC_NORM sobre target 1080x2340) donde cae el pivote del root
    "char_size": [941, 1672],    // "espacio personaje" en px (dims de la ilustración fuente)
    "scale": 1.15,               // charPx -> px de referencia (1080x2340)
    "loop_seconds": 4.2,
    "easing": "smooth",          // "linear" | "smooth" (smoothstep por segmento)
    "bones": [
      { "id":"root",     "parent":null,   "sprite":null,        "pivot_px":[470,869],
        "keyframes":[{"t":0,"x":0,"y":0,"rotation":-0.4,"scale":1},{"t":0.5,"x":8,"y":-13,"rotation":0.5,"scale":1.012},{"t":1,"x":0,"y":0,"rotation":-0.4,"scale":1}] },
      { "id":"leg_up",   "parent":"root", "sprite":"rig_leg_up",   "pivot_px":[588,761], "offset_px":[0,0], "z":1,
        "keyframes":[{"t":0,"rotation":0.8},{"t":0.5,"rotation":-1.4},{"t":1,"rotation":0.8}] },
      { "id":"leg_bent", "parent":"root", "sprite":"rig_leg_bent", "pivot_px":[612,819], "offset_px":[0,0], "z":2,
        "keyframes":[{"t":0,"rotation":-0.9},{"t":0.5,"rotation":1.1},{"t":1,"rotation":-0.9}] },
      { "id":"torso",    "parent":"root", "sprite":"rig_torso",    "pivot_px":[485,744], "offset_px":[0,0], "z":3,
        "keyframes":[{"t":0,"rotation":0},{"t":1,"rotation":0}] },
      { "id":"arm",      "parent":"torso","sprite":"rig_arm",      "pivot_px":[343,761], "offset_px":[0,0], "z":4,
        "keyframes":[{"t":0,"rotation":-1.8,"scale":0.995},{"t":0.47,"rotation":2.2,"scale":1.018},{"t":1,"rotation":-1.8,"scale":0.995}] },
      { "id":"head",     "parent":"torso","sprite":"rig_head",     "pivot_px":[381,560], "offset_px":[0,0], "z":5,
        "keyframes":[{"t":0,"rotation":-1.2},{"t":0.5,"rotation":1.5},{"t":1,"rotation":-1.2}] }
    ]
  }]
}
```

**Espacios (explícitos, para evitar la ambigüedad "normalizado sobre qué" del prototipo Codex):**
- `pivot_px`, `offset_px`, y `keyframes.x/y` viven en **espacio personaje** (px de la ilustración 941x1672).
- `offset_px` = esquina sup-izq del PNG recortado dentro de la ilustración. **Lo emite el pipeline Python** (bbox del recorte); los `[0,0]` de arriba son placeholders.
- `pivot_px` mapeado del RIG_SPEC de Codex: `pivot_px = pivot_norm * char_size`.
- `anchor` usa la misma convención que `params.x/y` de sprites (compatible con el editor actual).
- **Jerarquía ajustada vs Codex**: las dos piernas cuelgan de `root` (no de `torso`) — en la pose de impacto no deben heredar el vaivén del torso o se abren huecos en la cadera. Cabeza y brazo sí de `torso`.

### 3. Matemática de composición (Android Matrix, semántica `post*`)

**Local del hueso** `L_b` (articulado en su pivote, espacio personaje):
```
local.reset()
local.postTranslate(-pivotX, -pivotY)          // pivote al origen
local.postScale(s, s)                          // escala sobre pivote
local.postRotate(rot)                          // rota sobre pivote
local.postTranslate(pivotX + dx, pivotY + dy)  // regresa + traslación animada
```
**Mundo** `W_b` (topológico, padre antes que hijo): `world.set(local); world.postConcat(parentWorld)`.
**Global** `G` (espacio personaje → pantalla, con subjectFactor):
```
f  = subjectFactor(surfaceW, surfaceH)          // min(sw/1080, sh/2340)
k  = rig.scale * f
ax = surfaceW/2 + (anchor.x - 0.5) * 1080 * f   // = SceneCoords.spriteDrawCenter
ay = surfaceH/2 + (anchor.y - 0.5) * 2340 * f
G.reset(); G.postTranslate(-rootPivotX,-rootPivotY); G.postScale(k,k); G.postTranslate(ax,ay)
```
El root es un hueso más: `W_root = G · L_root` (su bob arrastra todo). Los px del keyframe se vuelven `px*k` físicos → cross-aspect correcto gratis.
**Dibujo por parte** (el crop arranca en su `offset_px`):
```
draw.reset()
draw.postTranslate(offsetX, offsetY)   // crop -> espacio personaje (bmpScale=1 con high_res)
draw.postConcat(worldOf(bone))         // -> pantalla
canvas.drawBitmap(bmp, draw, paintFilterBitmap)
```

### 4. Cambios en Kotlin (mínimos)
| Archivo | Cambio | ~Líneas |
|---|---|---|
| `scene/SceneSpec.kt` | `RigDef`+`BoneDef`+`BoneKeyframe` con parse defensivo; `rigs: List<RigDef>` (`j.optJSONArray("rigs")`) | ~70 |
| `scene/RigController.kt` (NUEVO) | ordena huesos topológicamente, pre-rellena canales de keyframes, `draw(canvas,sw,sh)` con matrices §3. **Cero allocations por frame** (matrices pre-alocadas) | ~180 |
| `renderers/SpriteSheet.kt` | accessor `currentBitmap(): Bitmap?`. **NO tocar `drawAt`** | ~5 |
| `scene/CanvasSceneRenderer.kt` | crear `rigControllers` en `ensureLoaded()`; en `draw()` agregar cada rig como `DrawItem(rig.z){...}` al interleaving; `needsContinuousAnimation` incluye rigs; invalidar en hot-reload | ~15 |

Sin cambios en Dart/MainActivity/service. Una sola recompilación; luego todo el tuning es editar JSON (hot-reload 1 Hz existente).

### 5. Pipeline de separación (`tools/rig/cut_rig_parts.py`, PIL+numpy+scipy)
Por cada hueso con `region` del RIG_SPEC:
1. Polígono a px: `pts = [(u*941, v*1672) for u,v in region]`.
2. Máscara `L` con `ImageDraw.polygon`.
3. **Dilatación +14 px** (`MaxFilter(29)` o `binary_dilation` r=14) → partes vecinas comparten franja en la articulación (anti-huecos con rotaciones ≤2°).
4. **Feather** `GaussianBlur(5)` → borde alfa suave (anti-costuras).
5. `part_alpha = np.minimum(alpha_original, mask)` — el contorno real del personaje manda; el feather solo actúa en cortes internos.
6. Crop a `mask.getbbox()` + pad 4 px; **guardar `offset_px = (bbox[0],bbox[1])`**.
7. Salidas: `parts/<bone>/frame_001.png` + `rig_parts_manifest.json` (offset/size/pivot por hueso) + **el bloque `rigs` del spec ya generado** + control visual:
   - `debug_regions.png`: ilustración con cada polígono etiquetado (validar la "raised_leg" sospechosa).
   - `debug_recompose.png`: las partes re-compuestas en sus offsets por z → debe verse idéntica al original (assert diff numpy).
8. **Assert de cobertura**: unión de regiones dilatadas cubre 100% del alfa (píxeles huérfanos = 0).
9. Empaquetado: cada parte a ZIP en bucket `wallpaper-sprites` bajo `rigs/heroina_v1/<parte>.zip` (pipeline de sprites de siempre). Para iterar sin subir: `adb run-as com.orbix.pixora` copia directo a `filesDir/sprites/rigs/heroina_v1/<parte>/`.

### 6. Animación
- Sampling por **reloj monotónico** (`System.nanoTime`), NO por tick: `phase = (elapsed % loop)/loop`; segmento lineal + **smoothstep** (`u*u*(3-2u)`) por canal (x,y,rotation,scale).
- Presupuesto de movimiento (anti-costura, límite ~2.5°): root ±8/±13 px, ±0.5°, scale→1.012 (mueve todo, 70% de la vida); head ±1.5°; arm −1.8°→+2.2°; piernas ≤1.4°; torso quieto en v1. Empezar con los valores de Codex y tunear en vivo.

### 7. Riesgos
1. **Descarga de sprites `preload` desde Dart** — supuesto a verificar (el downloader escanea `sprites[].manifest_key` sin filtrar por behavior). Fallback: `run-as` mete assets directo → no bloquea el slice.
2. **Regiones de Codex mal etiquetadas** (raised_leg) → `debug_regions.png` antes de compilar.
3. **Costuras visibles en device** (el preview de escritorio miente) → dilatación+feather + movimiento conservador + tuning en vivo.
4. **Perf**: 5 drawBitmap con matriz/frame — fracción del costo histórico de 4 layers full-screen; vigilar logcat. Plan B: prescalar crops a `k` una vez por surface.
5. **Cache de assets al iterar** → bump `revision` / re-push con `run-as`.

### Orden de ejecución (para verlo en el Samsung)
1. Python cutter → partes + debug images → **validación visual de Eduardo**.
2. Kotlin (§4) → `flutter build apk --debug` → install en RF8X903KZ3K.
3. Assets al device por `run-as` + spec a `scene_specs/` + aplicar escena.
4. Tuning en vivo (editar JSON → push → hot-reload ~5 s).
5. Smoke: 10 min, logcat (fps/OOM/FATAL), lock/unlock.

### Diferido (no en el slice)
Publicación a Supabase, editor visual de rig, movimientos amplios con partes IA, múltiples rigs por escena (formato ya lo soporta), inpaint del fondo bajo solapes.

### Riesgo difícil de revertir
El **formato del bloque `rigs`**: una vez publicado contenido, el parser viejo lo ignora (degradación limpia a solo-fondo por parsing defensivo), pero cambiar campos rompe specs subidos. Por eso los espacios son explícitos y estables (px de personaje + `char_size` + `scale`).
