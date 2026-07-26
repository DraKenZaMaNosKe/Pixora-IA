"""Procesa el astronauta rig de Codex: cropea las 8 partes full-canvas a su
bbox, convierte RIG_SPEC_PRODUCTION.json al formato rigs[] de Pixora, arma el
staging (spec + bg webp + partes) y un debug_recompose para validar.
"""
import io, json, shutil, sys
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
CHAR = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/astronauta_nebula_rig_production")
SID = "astronauta_nebula_flota"
RIG_DIR = "rigs/astronauta_v1"
OUT = CHAR / "rig_out"
STAGE = OUT / "device_staging"
W, H = 1080, 1920

prod = json.loads((CHAR / "RIG_SPEC_PRODUCTION.json").read_text(encoding="utf-8"))
tracks = prod["animations"]["zero_gravity_idle"]["tracks"]

if STAGE.exists(): shutil.rmtree(STAGE)
(STAGE / "scene_specs").mkdir(parents=True, exist_ok=True)
(STAGE / f"scene_layers/{SID}").mkdir(parents=True, exist_ok=True)

bones_out, sprites_out = [], []
recompose = Image.new("RGBA", (W, H), (0, 0, 0, 0))
# ordenar por z para recompose correcto
for b in sorted(prod["bones"], key=lambda x: x.get("z", 0)):
    bid = b["id"]
    pivot_px = [round(b["pivot"][0] * W), round(b["pivot"][1] * H)]
    bone = {"id": bid, "parent": b.get("parent"),
            "sprite": None, "pivot_px": pivot_px, "z": b.get("z", 0)}
    if bid in tracks:
        bone["keyframes"] = tracks[bid]
    if b.get("file"):
        bbox = b["bbox_px"]
        x, y, w, h = bbox["x"], bbox["y"], bbox["w"], bbox["h"]
        part = Image.open(CHAR / b["file"]).convert("RGBA")
        crop = part.crop((x, y, x + w, y + h))
        dst = STAGE / f"sprites/{RIG_DIR}/{bid}"; dst.mkdir(parents=True, exist_ok=True)
        crop.save(dst / "frame_001.png")
        recompose.alpha_composite(crop, (x, y))
        bone["sprite"] = f"rig_{bid}"
        bone["offset_px"] = [x, y]
        sprites_out.append({"name": f"rig_{bid}", "manifest_key": f"{RIG_DIR}/{bid}",
                            "behavior": "preload", "params": {"high_res": True}})
        print(f"  ✓ {bid:20} bbox=({x},{y},{w},{h}) pivot={pivot_px} z={b.get('z')}")
    else:
        print(f"  · {bid:20} (root, pivot={pivot_px})")
    bones_out.append(bone)

rig_block = {"name": "astronauta", "z": 10, "anchor": [0.5, 0.55],
             "char_size": [W, H], "scale": 1.0,
             "loop_seconds": prod["animations"]["zero_gravity_idle"]["duration_ms"] / 1000.0,
             "easing": "smooth", "bones": bones_out}

spec = {
    "id": SID, "schema_version": 1, "type": "canvas_scene",
    "image_layers": [{"key": "bg", "url": "https://placeholder/bg.webp", "z": 0,
                      "parallax_factor": 0.05, "scroll_factor": 0.0}],
    "sprites": sprites_out,
    "rigs": [rig_block],
}
(STAGE / "scene_specs" / f"{SID}.json").write_text(
    json.dumps(spec, indent=2, ensure_ascii=False), encoding="utf-8")

# bg + master + preview a partir de los assets 1080x1920 de Codex
Image.open(CHAR / "fondo_limpio_1080x1920.png").convert("RGB").save(
    STAGE / f"scene_layers/{SID}/bg.webp", "WEBP", quality=88, method=6)
Image.open(CHAR / "wallpaper_estatico_1080x1920.png").convert("RGB").save(
    STAGE / "master.webp", "WEBP", quality=88, method=6)

# debug recompose sobre el fondo → debe verse como el astronauta ensamblado
bg = Image.open(CHAR / "fondo_limpio_1080x1920.png").convert("RGBA")
comp = bg.copy(); comp.alpha_composite(recompose)
DBG = Path(r"C:/Users/lalo/Desktop/RIG_HEROINA_REVISAR"); DBG.mkdir(exist_ok=True)
comp.convert("RGB").save(DBG / "astronauta_recompose.png")

print(f"\n[OK] {len(sprites_out)} partes · staging en {STAGE}")
print(f"debug_recompose -> {DBG/'astronauta_recompose.png'}")
