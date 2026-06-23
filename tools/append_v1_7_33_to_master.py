"""Append §12.33 al master doc con notas de v1.7.33+76.

Bump 1.7.32+75 → 1.7.33+76. Fixes críticos:
  · Cache cleanup en Daily cuando cambia categoría
  · Manual apply (set/setLive) detiene rotation engines
  · Migration PAISAJISMO→PAISAJES
  · +60 wallpapers (10 paisajes + 10 pano + 20 mix + 8 mix2)
"""
import hashlib
import shutil
import sys
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
    print(f"[snapshot] already exists: {snap_path.name}")

doc = Document(str(SRC))


def kv(label, value):
    p = doc.add_paragraph()
    p.add_run(label + ": ").bold = True
    p.add_run(value)


def bullet(text):
    doc.add_paragraph(text, style="List Bullet")


doc.add_heading("12.33 v1.7.33+76 — 23 de junio 2026", level=2)
kv("Versión", "1.7.33 (versionCode 76)")
kv("Track", "prueba_cerrada (Closed testing — 177 países/regiones)")
kv("Fecha", "2026-06-23")
kv("Bump", "1.7.32+75 → 1.7.33+76")

doc.add_paragraph(
    "Release crítico para Pixora Daily — arregla dos bugs UX que rompían "
    "la experiencia: la rotación pegaba wallpapers de la categoría "
    "anterior al cambiar de filtro, y el apply manual era sobreescrito "
    "por la siguiente rotación. Además ship el catálogo nuevo: 60+ "
    "wallpapers (paisajes + panorámicas + mix anime/gaming/scifi)."
)

doc.add_heading("Fixes críticos", level=3)
bullet(
    "Daily cache cleanup on category switch: AutoRotateWorker.start() "
    "ahora compara los archivos del `auto_rotate_cache/` con los IDs "
    "del catalog nuevo. Si hay mismatch (archivos huérfanos de la "
    "categoría anterior), borra todo el cache y resetea current_path. "
    "El prefetch worker re-descarga solo los wallpapers de la nueva "
    "categoría. Síntoma original: PAISAJES mostraba Elvira/Seiya/etc. "
    "Root cause: catalog SharedPrefs sí se updateaba pero la rotación "
    "in-service picked from filesystem que tenía los archivos viejos."
)
bullet(
    "Manual apply stops rotation engines: WallpaperService.setWallpaper "
    "y setLiveWallpaper ahora invocan WallpaperEngineCoordinator.stopAll() "
    "ANTES de ejecutar. Antes: user aplicaba un wallpaper manual pero "
    "Daily/DayCycle/Story seguían corriendo y al siguiente tick (≤5 min) "
    "sobreescribían la selección. Después: manual apply tiene prioridad, "
    "rotation se detiene silenciosa. stopAll() es idempotent + "
    "defensive (try-catch interno) — si falla el stop, el apply no "
    "crashea (worst case: rotación glitch, no crash)."
)
bullet(
    "Migration PAISAJISMO→PAISAJES: rename del enum value in-place "
    "(operación instantánea, no afecta filas). El código Flutter "
    "filtraba `w.category=='PAISAJES'` pero el enum era `PAISAJISMO`, "
    "por eso el filtro de Daily PAISAJES daba pool vacío y vuelve a "
    "la pantalla anterior. Arreglo backend-only — aplicable también "
    "a v1.7.30 actual sin update."
)

doc.add_heading("Catálogo nuevo (60+ wallpapers)", level=3)
bullet(
    "Pack PAISAJES portrait (10): paisaje_valle_montana_amanecer, "
    "playa_tropical_atardecer, lagos_alpinos_nieve, rio_bosque_otonal, "
    "colinas_verdes_roble, lago_muelle_atardecer, via_lactea_desierto, "
    "bosque_bambu_rayos, acantilado_mar_stacks, lavanda_blue_hour. "
    "Categoría PAISAJES, daily_eligible=true, sort 1039-1048."
)
bullet(
    "Pack PANORAMIC 16:9 (10): playa_nube_corazon, amapolas_bahia, "
    "lago_camino_atardecer, valle_alpino_flores, luna_enorme_acantilado, "
    "lago_asters_morados, pasarela_bosque_otonal, playa_blue_hour_lavanda, "
    "lago_amanecer_niebla, valle_alpino_arcoiris. Sort 1049-1058."
)
bullet(
    "Pack PANORAMIC mix (20): bosque_hongos_magicos, luna_gigante_barquito, "
    "lago_alpino_reflejo_perfecto, pueblo_mx_papel_picado, "
    "calle_victoriana_pixel, girasoles_tormenta, pueblo_pixel_montanas, "
    "capilla_swamp_gotico, islas_flotantes_cristales, arbol_solitario_tormenta, "
    "picnic_anime_molino, muelle_otono_sillas, aurora_fogata_pixel, "
    "hospital_abandonado_niebla, estacion_lluvia_anime, torii_luna_roja, "
    "playa_arcoiris_rayos, playa_pixel_synthwave, valle_sakura_anime, "
    "arbol_colina_rayos. Sort 1059-1078."
)
bullet(
    "Mix Pack 8 (5 static + 3 panoramic, anime/gaming/scifi): Beerus en "
    "trono cósmico, Finn&Jake bajo estrellas, Personajes asomándose puerta, "
    "Coyote/Correcaminos, Adventure Time Tierra Ooo, Zelda Master Sword, "
    "Pixel Palace Arcade, Wall-E con plantita. Sort 1079-1086."
)

doc.add_heading("Lecciones aprendidas", level=3)
bullet(
    "Dos capas de cache: cualquier sistema con (a) catalog en SharedPrefs "
    "y (b) filesystem cache de archivos descargados DEBE invalidar AMBAS "
    "cuando cambia el filtro. Sólo invalidar el catalog deja la rotación "
    "in-service usando archivos viejos del filesystem. Pattern: al "
    "cambiar filter, comparar nombres en filesystem vs IDs del catalog "
    "nuevo, borrar mismatches."
)
bullet(
    "El WallpaperEngineCoordinator solo cubre lo que sabe que coordina. "
    "Cuando agregas un nuevo entry-point que toca el wallpaper (apply "
    "manual, ad mode, story, etc), DEBES integrarlo al coordinator. "
    "Patrón seguro: cualquier apply imperativo invoca stopAll() defensivo "
    "(try-catch) al principio para tener mutex implícito."
)
bullet(
    "Enums Postgres: renombrar enum values via `ALTER TYPE ... RENAME "
    "VALUE` es instantáneo y no afecta filas (Postgres mantiene refs "
    "por OID interno). Útil cuando el frontend cambió de string pero "
    "el backend aún tiene el viejo. Disponible desde PostgreSQL 10."
)

doc.save(str(SRC))
print("[OK] §12.33 appended")
