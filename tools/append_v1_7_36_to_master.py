"""Append §12.36 al master doc con notas de v1.7.36+79.

Bundle de v1.7.34 (sort DESC + PANORAMIC pill + scanline fix + type field)
+ v1.7.35 (OOM fix) + v1.7.36 (Mystery Cards 3 fases). 3 versiones
intermedias compiladas localmente pero NO subidas a Play Store —
v1.7.36 es lo que llega al usuario.
"""
import hashlib, shutil, sys
from datetime import date
from pathlib import Path
from docx import Document

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SRC = Path(r"G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx")
SNAP = Path(r"D:/Orbix/Pixora-IA/docs/master_doc_snapshots")
SNAP.mkdir(parents=True, exist_ok=True)
sha8 = hashlib.sha256(SRC.read_bytes()).hexdigest()[:8]
snap_path = SNAP / f"{date.today().isoformat()}_{sha8}.docx"
if not snap_path.exists():
    shutil.copy2(SRC, snap_path)
    print(f"[snapshot] {snap_path.name}")
else:
    print(f"[snapshot] already exists")

doc = Document(str(SRC))


def kv(label, value):
    p = doc.add_paragraph()
    p.add_run(label + ": ").bold = True
    p.add_run(value)


def bullet(text):
    doc.add_paragraph(text, style="List Bullet")


doc.add_heading("12.36 v1.7.36+79 — 24 de junio 2026", level=2)
kv("Versión", "1.7.36 (versionCode 79)")
kv("Track", "prueba_cerrada")
kv("Fecha", "2026-06-24")
kv("Bundle", "v1.7.34 + v1.7.35 + v1.7.36 — versiones intermedias compiladas pero no subidas a Play")

doc.add_paragraph(
    "Release feature-rich: introduce Mystery Cards como mecánica de "
    "engagement + monetización opt-in, arregla OOM crítico en devices "
    "low-memory, y mejora UX visual del feed (newest first + badges)."
)

doc.add_heading("Feature destacado — Mystery Cards", level=3)
bullet(
    "1 de cada ~12 cards del grid aparece como Mystery con efecto "
    "synthwave Glitch Neon: rejilla 3D perspective al piso + ??? cyan "
    "con RGB split (3 capas magenta+cyan offset) + border magenta. "
    "Tap → flip Y 700ms → revela el wallpaper real."
)
bullet(
    "Auto-hide 3 segundos post-reveal — si el user no abre el preview, "
    "la card vuelve al estado mystery. Permite re-suspense + previene "
    "que el grid se llene de cards 'fake reveal' que ya el user vio."
)
bullet(
    "Exclusión persistente vía MysteryExclusionService (Hive box "
    "`mystery_excluded`). Al aplicar wallpaper, WallpaperStatsService."
    "trackInstall hook agrega el ID al box — no vuelve a aparecer "
    "como mystery NUNCA. Favoritos también excluidos (lectura directa "
    "del Hive box `favorites`)."
)
bullet(
    "Bias hacia contenido nuevo (Phase 2): wallpapers con isNew==true "
    "(creado <14d O badge='NEW') tienen 2× probabilidad de ser mystery "
    "(mod 6 vs mod 12). Mantiene el feed fresco."
)
bullet(
    "Tesoro Bonus (Phase 3 — monetización): 1 de cada 5 mystery reveals "
    "(hash determinístico) → en vez del wallpaper directo, muestra "
    "card DORADA con '🎁 TESORO BONUS' + sparkles + foil sweep + CTA "
    "'DESCUBRIR'. Tap → AdService.showInterstitialAd() → al cerrar "
    "earnFromAd() automático (15 diamantes) → revela wallpaper como "
    "recompensa visual. Premium subs skip ad inmediato."
)
bullet(
    "Decisión económica Eduardo: cero diamantes extra del Tesoro Bonus "
    "porque eCPM LATAM ($2.50 USD) vs costo Grok IA ($0.03 USD) deja "
    "margen apretado. Los 15 del ad ya son suficiente recompensa."
)

doc.add_heading("Fixes críticos heredados (v1.7.35)", level=3)
bullet(
    "OOM Samsung A15 (4GB): LMK killed Pixora a 658 MB RSS. Tres tweaks "
    "redujeron consumo a ~428 MB (-35%): "
    "(1) CachedWallpaperImage.maxDecodedWidth default 320→240 px "
    "(bitmap −44% memoria), "
    "(2) imageCache cap 40→25 MB y 50→30 imágenes, "
    "(3) wallpaper_carousel_row.cacheExtent 150→80."
)

doc.add_heading("Mejoras visuales heredadas (v1.7.34)", level=3)
bullet(
    "sort_order DESC en CatalogService + 8 lugares en wallpaper_providers. "
    "Wallpapers más nuevos primero en todas las listas (Panorámicos, "
    "Anime, Gaming, Calendar, Mitología, Arte, search). Antes ASC ponía "
    "los primeros que subimos al inicio — feed se sentía viejo."
)
bullet(
    "Pill ⟷ PANORAMIC magenta en el holocard del viewer cuando "
    "isPanoramic. User identifica de un vistazo el tipo."
)
bullet(
    "Scanline del viewer ya NO es permanente: cambió de .repeat() a "
    ".forward() single-pass 2.5s + re-trigger en onPageChanged. Efecto "
    "scan-and-reveal de bienvenida sin distracción eterna."
)
bullet(
    "Wallpaper.type field nuevo (mapea wallpaper_type enum de Postgres). "
    "isPanoramic ahora revisa 3 señales en orden: type=='panoramic' "
    "(explicit) → ratio>=3.0 → category=='PANORAMIC'. Catches panos "
    "que viven en categories thematicas (ej. Adventure Time pano en "
    "ANIME)."
)

doc.add_heading("Cambios backend (sin requerir update de app)", level=3)
bullet(
    "3 wallpapers recategorizados a PANORAMIC: pano_adventure_time_noche, "
    "pano_coyote_correcaminos, pano_pixel_palace_arcade. Defensive — "
    "v1.7.30 actual también los detecta como pano."
)
bullet(
    "Pano nuevas (Goku Shenron + Ghibli colina) recategorizadas a "
    "PANORAMIC."
)

doc.add_heading("Lecciones aprendidas", level=3)
bullet(
    "Memory pressure en devices low-end es la frontera #1 de retención. "
    "Samsung A15 (4GB) marca 'low_memory_device=true' y LMK mata "
    "agresivamente cualquier app > 600 MB. Cap memCacheWidth + imageCache "
    "+ cacheExtent es la receta — sin ellos, scroll moderado mata la app."
)
bullet(
    "Gamification > funcionalidad pura: el Mystery Card no resuelve "
    "ningún problema técnico, pero mantiene al user en el feed más "
    "tiempo (curiosidad por revelar) — y la dopamina del reveal + "
    "ocasional Tesoro Bonus monetiza sin sentirse forzado."
)
bullet(
    "Defensive coding en widgets de UX: si Hive, AdService o haptic "
    "feedback fallan, el Mystery Card debe seguir funcionando (worst "
    "case sin la feature extra). Por eso TODO está envuelto en try-catch."
)

doc.save(str(SRC))
print("[OK] §12.36 appended")
