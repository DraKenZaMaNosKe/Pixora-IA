"""Append the Tecnología Generada (Lecciones Técnicas) section to the
Pixora master doc. Every entry documents a real problem we hit,
the root cause, and the pattern to follow next time."""
import sys
sys.stdout.reconfigure(encoding="utf-8")

from docx import Document
from pathlib import Path
import hashlib, shutil
from datetime import date

SRC = Path(r"G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx")
SNAP = Path(r"D:/Orbix/Pixora-IA/docs/master_doc_snapshots")
SNAP.mkdir(parents=True, exist_ok=True)
sha8 = hashlib.sha256(SRC.read_bytes()).hexdigest()[:8]
snap = SNAP / f"{date.today().isoformat()}_{sha8}_pre-tech.docx"
if not snap.exists():
    shutil.copy2(SRC, snap)
    print(f"Snapshot: {snap.name}")

doc = Document(str(SRC))

doc.add_heading("24  TECNOLOGÍA GENERADA · Lecciones Técnicas", level=1)

intro = doc.add_paragraph(
    "Bitácora de descubrimientos técnicos hechos durante el desarrollo "
    "de Pixora. Cada entrada documenta UN problema concreto que costó "
    "tiempo resolver, la causa raíz, y el patrón a seguir la próxima vez. "
    "La idea: cada hora gastada en debug se convierte en 5 minutos la "
    "próxima vez que aparezca el mismo síntoma."
)

# 24.1 Cache stale
doc.add_heading("24.1 Cache stale en wallpapers (re-descarga forzada)", level=2)
doc.add_paragraph(
    "SÍNTOMA: Generamos una nueva versión de un wallpaper, la subimos a "
    "Supabase, pero al reaplicar en el device el usuario sigue viendo la "
    "versión vieja."
)
doc.add_paragraph(
    "CAUSA RAÍZ: El servicio _downloadPhase() en arcano_page.dart cachea "
    "por NOMBRE de archivo. Si el archivo ya existe localmente con ese "
    "nombre, se reutiliza sin verificar si el contenido remoto cambió. "
    "No hay ETag/hash/Last-Modified check."
)
doc.add_paragraph(
    "WORKAROUND ACTUAL durante dev: borrar archivos cacheados via adb antes "
    "de reaplicar:"
)
doc.add_paragraph(
    "adb -s RF8X903KZ3K shell run-as com.orbix.pixora sh -c "
    "\"rm -fv /data/data/com.orbix.pixora/app_flutter/wallpapers/<filename>*.webp\"",
    style="Quote",
)
doc.add_paragraph(
    "SOLUCIÓN DEFINITIVA (Task #109 pendiente): Hive cache + ETag check. "
    "Antes de servir el archivo cacheado, hacer HEAD request al CDN. Si el "
    "ETag remoto difiere del guardado, redownload. Costo ~20ms por "
    "verificación, elimina el problema PARA SIEMPRE."
)
doc.add_paragraph(
    "PATRÓN: Cualquier asset cacheable que cambia con el tiempo "
    "(wallpapers, sprites, configs, scene specs) DEBE tener un mecanismo "
    "de invalidación. Por defecto: ETag/Last-Modified check. Si el round "
    "trip es prohibitivo: incluir version/hash en el filename."
)

# 24.2 Samsung wallpaper treatment
doc.add_heading("24.2 Samsung trata WallpaperService custom diferente que ImageWallpaper", level=2)
doc.add_paragraph(
    "SÍNTOMA: Wallpaper canvas_scene custom NO escrolla horizontalmente "
    "entre páginas del home, mientras que un wallpaper panorámico "
    "estático aplicado via setBitmap SÍ lo hace fluidamente."
)
doc.add_paragraph(
    "CAUSA RAÍZ: Samsung One UI reserva el scroll panorámico nativo "
    "(compositor-level) para ImageWallpaper service estático aplicado "
    "vía WallpaperManager.setBitmap(). Live wallpapers custom "
    "(PixoraWallpaperService) reciben menos eventos onOffsetsChanged, "
    "son frozen agresivamente por Samsung Freecess (battery saver), y "
    "no tienen scroll nativo aunque uno llame a "
    "suggestDesiredDimensions(2*W, H)."
)
doc.add_paragraph(
    "DEBUG QUE GASTAMOS: 4+ horas tratando de hacer scrollear el Iah "
    "como canvas_scene Live. Probamos: setOffsetNotificationsEnabled, "
    "suggestDesiredDimensions con SET_WALLPAPER_HINTS permission, touch "
    "handler manual, two-stage lerp + velocity inertia, gates en xStep. "
    "NADA funcionó porque la limitación es a nivel del compositor "
    "Samsung, no a nivel de nuestro código."
)
doc.add_paragraph(
    "SOLUCIÓN: Para wallpapers que necesitan scroll panorámico, usar "
    "SIEMPRE imagen estática 4192x1024 (ratio 4:1 landscape) aplicada "
    "via setBitmap. Samsung detecta panorámica por aspect ratio y "
    "escala automáticamente para fit screen height, dejando ~8499 px de "
    "scroll horizontal. Para efectos animados que NO necesitan scroll, "
    "canvas_scene Live wallpaper sigue siendo válido (tilt parallax con "
    "gyro funciona bien)."
)
doc.add_paragraph(
    "PATRÓN ARQUITECTÓNICO: si el wallpaper espera scroll horizontal, "
    "NUNCA usar WallpaperService custom — usar imagen estática. Si "
    "espera animación continua (sprites, particles, scene events), usar "
    "Live wallpaper pero documentar que NO tendrá scroll nativo."
)

# 24.3 Aspect ratio for panoramic
doc.add_heading("24.3 Aspect ratio crítico para panoramic en Samsung", level=2)
doc.add_paragraph(
    "SÍNTOMA: Wallpaper de 4192x2340 (ratio 1.79) aplicado como "
    "panorámico se ve recortado al centro, sin posibilidad de scroll. "
    "Mismo wallpaper a 4192x1024 (ratio 4.09) hace scroll perfecto."
)
doc.add_paragraph(
    "CAUSA RAÍZ: Samsung escala el wallpaper para FIT screen HEIGHT. Si "
    "la imagen ya tiene la misma altura que la pantalla, no hay extra "
    "horizontal disponible para pannear. Solo cuando la imagen es "
    "LANDSCAPE (más ancha que alta), Samsung escala vertical y deja "
    "sobrante horizontal."
)
doc.add_paragraph(
    "DEBUG ESPECÍFICO: La primera versión del Iah panoramic la generé a "
    "4192x2340 pensando \"más alto = más calidad\". Al instalar Samsung "
    "la mostró centrada y recortada porque ya \"caía justo\" en pantalla. "
    "Al rehacer a 4192x1024, Samsung escaló a ~9579x2340 y el scroll "
    "panorámico funcionó perfectamente."
)
doc.add_paragraph(
    "PATRÓN: panorámicos siempre deben tener ratio >= 3:1 (ej. 4192x1024 "
    "= 4.09:1, 3584x1184 = 3.03:1 como Akuma). Estándar Pixora oficial: "
    "4192x1024. Documentado en CLAUDE.md."
)

# 24.4 UI contrast on art bg
doc.add_heading("24.4 Contraste de elementos UI sobre fondos artísticos", level=2)
doc.add_paragraph(
    "SÍNTOMA: Glifos zodiacales coloreados por elemento se perdían "
    "visualmente sobre el fondo cósmico estrellado del Iah. Pasteles "
    "suaves (#B8A4E3 lila, #7CB872 jade) eran tragados por las "
    "constelaciones del bg art."
)
doc.add_paragraph(
    "SOLUCIÓN: Tres mejoras combinadas — saturación BOOSTED (pastel suave "
    "→ vibrante), tamaño glyph aumentado (34px → 54px), vignette radial "
    "detrás del glifo (gradiente suave de transparente a oscuro que "
    "aísla el color del bg sin verse como sticker rectangular)."
)
doc.add_paragraph(
    "ITERACIÓN POSTERIOR: Los glifos a 54px / 74px se sentían demasiado "
    "grandes como hero element. Reducimos a 32px / 44px (multiplicador 1.0 "
    "en lugar de 1.6) para que se lean como \"asterismos\" pequeños "
    "alrededor del altar, no como protagonistas. Géminis del usuario "
    "mantuvo su prominencia con halo + constelación overlay."
)
doc.add_paragraph(
    "PATRÓN: Cualquier glifo / texto / icono UI sobre fondo artístico "
    "necesita: (a) saturación alta del color de primer plano, (b) tamaño "
    "calibrado por jerarquía visual (no \"todo grande\"), (c) backing "
    "layer (vignette suave o stroke) que aísle sin verse pegado."
)

# 24.5 adb binary corruption
doc.add_heading("24.5 adb shell cat corrompe binarios en Windows", level=2)
doc.add_paragraph(
    "SÍNTOMA: adb shell cat /data/.../file.webp > local.webp produce un "
    "archivo corrupto que PIL no puede decodificar (visualmente: ruido "
    "purpura)."
)
doc.add_paragraph(
    "CAUSA RAÍZ: En Windows con adb, \"shell cat\" usa stdout TEXT mode, "
    "que convierte LF (0x0A) → CRLF (0x0D 0x0A) en cada byte 0x0A del "
    "binario, corrompiendo el archivo."
)
doc.add_paragraph(
    "SOLUCIÓN: Usar adb exec-out (binario nativo, sin conversión). Para "
    "archivos protegidos con run-as, exec-out funciona:"
)
doc.add_paragraph(
    "adb exec-out \"run-as com.orbix.pixora cat /path/file.webp\" > local.webp",
    style="Quote",
)
doc.add_paragraph(
    "ALTERNATIVA: adb pull funciona perfecto para archivos accesibles "
    "(no necesita run-as) sin problemas de codificación."
)

# 24.6 Composition zoom for screen viewport
doc.add_heading("24.6 Zoom-out de composición para viewport phone", level=2)
doc.add_paragraph(
    "SÍNTOMA: Wallpaper diseñado al 100% del viewport panorámico se ve "
    "demasiado grande / saturado en el phone. Elementos importantes "
    "quedaban cortados o el usuario veía solo un detalle."
)
doc.add_paragraph(
    "PROBLEMA ESPECÍFICO IAH: Generábamos el altar (frame, moon, wheel, "
    "glyphs) a height=1024 (matching panorama height). Cuando Samsung "
    "escalaba 4192x1024 → 9579x2340, el altar quedaba con 2340px de alto "
    "ocupando casi toda la pantalla. Los signos del wheel quedaban en los "
    "bordes o cortados."
)
doc.add_paragraph(
    "SOLUCIÓN: Introdujimos un factor ALTAR_ZOOM = 0.60. Los layers del "
    "altar se escalan a 60% del panorama height (614 px en vez de 1024) "
    "y se centran verticalmente. El cosmos de fondo permanece a 100% "
    "(el universo no se achica). Resultado: todo el wheel zodiacal cabe "
    "en una sola pantalla del phone con espacio para respirar."
)
doc.add_paragraph(
    "PATRÓN: Cuando diseñes un wallpaper, recuerda que el panorama va a "
    "ser escalado por Samsung. Diseña la composición para que el "
    "elemento focal ocupe ~50-60% del viewport phone, NO 100%. Deja "
    "padding generoso. La simulación con crop(W//2-540, 0, W//2+540, 2340) "
    "te da una preview real de lo que el usuario verá en home."
)

# 24.7 Background art with embedded zodiac
doc.add_heading("24.7 Background art con elementos pre-baked: cuidado con duplicación", level=2)
doc.add_paragraph(
    "SÍNTOMA: Generamos un background cósmico con \"constelaciones + glifos "
    "zodiacales decorativos\" via Gemini. Después al overlay nuestro propio "
    "wheel zodiacal, había duplicación: glifos del bg + glifos del wheel "
    "compitiendo visualmente."
)
doc.add_paragraph(
    "CAUSA RAÍZ: El bg image (fondo_con_constelaciones.webp) ya tenía "
    "zodiacos drawn-into-the-art como decoración. Nuestro wheel encima "
    "agregó OTROS 12 zodiacos. El usuario vio 24 glifos confusos."
)
doc.add_paragraph(
    "SOLUCIÓN PARCIAL: Hicimos el wheel del altar más pequeño y los "
    "glifos del wheel más prominentes (color por elemento) para "
    "diferenciarlos de los del bg que son monocromáticos dorados."
)
doc.add_paragraph(
    "PATRÓN: Cuando pidas backgrounds artísticos a Gemini, sé EXPLÍCITO "
    "sobre lo que NO debe incluir. Para wallpapers donde vas a overlay "
    "elementos UI: \"NO incluir zodiac signs / NO text / NO main subjects "
    "in the center area\". Reservar zonas limpias en el bg para tus "
    "overlays."
)

doc.save(str(SRC))
print("OK appended section 24 (7 lessons)")
