"""Append §12.32 al master doc con notas de v1.7.32+75.

Bump 1.7.31+74 → 1.7.32+75. Cambios desde v1.7.30:
  · Anti-spam tap guards en visor (v1.7.31)
  · Fix viewer HUD reportar → RPC real
  · Fix pull-to-refresh Day Cycle (service cache vs Riverpod)
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


doc.add_heading("12.32 v1.7.32+75 — 22 de junio 2026", level=2)
kv("Versión", "1.7.32 (versionCode 75)")
kv("Track", "prueba_cerrada (Closed testing — 177 países/regiones)")
kv("Fecha", "2026-06-22")
kv("Bump", "1.7.31+74 → 1.7.32+75")

doc.add_paragraph(
    "Release puente sobre v1.7.30 — empaqueta el tap-guards de v1.7.31 "
    "que nunca llegó a Play Store + un fix de pull-to-refresh en Day "
    "Cycle. Mejora estabilidad de interacción y cierra el último loop "
    "del compliance Google Play AI policy."
)

doc.add_heading("Cambios visibles para el usuario", level=3)
bullet(
    "Anti-spam tap guards: los botones Aplicar / Favorito / Reportar "
    "del visor ahora se debouncean (700 ms–3 s según botón) — se acabó "
    "el aplicar wallpaper dos veces por error o mandar 2 reportes "
    "idénticos."
)
bullet(
    "Botón \"Reportar contenido\" del visor HUD ahora manda el reporte "
    "real al RPC report_wallpaper (antes mostraba snackbar fake — "
    "regresión introducida cuando se refactorizó el viewer)."
)
bullet(
    "Pull-to-refresh en Day Cycle: jala abajo y los temas nuevos "
    "aparecen al instante (antes la lista vieja del cache se "
    "quedaba hasta cold start)."
)

doc.add_heading("Cambios técnicos", level=3)
bullet(
    "TapGuardController (lib/core/utils/tap_guard.dart) — wrapper "
    "ligero con tryFire() que descarta llamadas dentro de un cooldown. "
    "Aplicado a apply (3 s), report (2 s), favorite (700 ms)."
)
bullet(
    "DayCyclePage.RefreshIndicator.onRefresh ahora llama "
    "DayCycleCatalogService.instance.fetchCatalog(forceRefresh: true) "
    "ANTES de invalidar el provider de Riverpod. El service tiene "
    "cache interno (_themes + _isCacheValid) que no se flushea por "
    "invalidar el provider — bug encubierto desde la migración de "
    "static themes a Storage JSON."
)
bullet(
    "Master switch showHudOverlays sigue en false por default (v1.7.29) "
    "— ningún cambio en HUDs para este release."
)

doc.add_heading("Cambios fuera del APK (entrega de contenido)", level=3)
bullet(
    "Pixora Admin Dashboard: nueva pestaña Day Cycle con CRUD "
    "(editar nombre/descripción/glow + borrar tema). El catálogo "
    "vive en day_cycle_catalog.json en Storage — el server mutate "
    "el JSON y re-PUT vía SERVICE_KEY."
)
bullet(
    "launch_admin_silent.vbs reescrito: kill instancias previas vía "
    "PowerShell Stop-Process filtrando por CommandLine + poll del "
    "puerto 5757 + ready-check de /api/stats antes de abrir el "
    "navegador. Doble click siempre arranca limpio sin tocar otros "
    "pythons en uso."
)
bullet(
    "Batch uploads desde 2026-06-21: Mundos Paralelos (5 panorámicas), "
    "Predator/Alien (5 panorámicas con nombres genéricos para evitar "
    "IP risk), Mix 06-21 (11 mixed), Megaman, Mario, Pokemon Café 3D, "
    "Rancho cozy (4 cards), Snoopy, Throotle 3D, Adventure Time pack "
    "(Jake day cycle + pano + static), Ventana Mexicana (primer day "
    "cycle), Batch B (Nave Interior + Pacman + Star Sheep Trooper + "
    "Egipto + Gatito Naranjoso)."
)
bullet(
    "_replace_asset.py helper: detecta tabla destino (wallpapers vs "
    "live_catalog) + actualiza image_size + dimensions + dispara FCM "
    "invalidate. Resuelve el bug \"reinstalé y sigo viendo la "
    "antigua\" — el cache del cliente verifica expectedSize."
)

doc.add_heading("Lessons learned", level=3)
bullet(
    "Cualquier ChangeNotifier singleton con cache interno DEBE tener "
    "su propio forceRefresh disponible para el pull-to-refresh. "
    "Invalidar el FutureProvider de Riverpod NO purga el cache del "
    "service — solo fuerza un nuevo .read() que el service responde "
    "con datos cached. Convención: pull-to-refresh siempre llama "
    "service.fetchX(forceRefresh: true) y DESPUÉS ref.invalidate()."
)
bullet(
    "Mock-then-forget anti-pattern: el botón \"Reportar contenido\" "
    "del visor era un snackbar fake en lo que se implementaba el RPC. "
    "Cuando v1.7.30 mergeó el RPC, el viewer no se actualizó. Audit "
    "post-release detectó vía Eduardo (\"ya envié 2 reportes, "
    "fíjate si se generaron\" → 0 rows). Acción: grep `mock|fake|TODO` "
    "antes de cada release de compliance."
)

doc.save(str(SRC))
print("[OK] §12.32 appended")
