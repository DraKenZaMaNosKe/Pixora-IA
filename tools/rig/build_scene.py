"""Arma el canvas_scene del rig: spec.json + bg.webp + partes, en un staging
listo para empujar al device por adb run-as. Lee el rig_block.json que emitió
cut_rig_parts.py.
"""
import json, shutil, sys
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
CHAR = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/heroina_candy_mecha_rig_v1")
RP = CHAR / "rig_parts"
STAGE = RP / "device_staging"
SCENE_ID = "heroina_candy_mecha_rig_v1"
RIG_DIR = "rigs/heroina_v1"

if STAGE.exists(): shutil.rmtree(STAGE)
(STAGE / "scene_specs").mkdir(parents=True, exist_ok=True)
(STAGE / f"scene_layers/{SCENE_ID}").mkdir(parents=True, exist_ok=True)

rig_block = json.loads((RP / "rig_block.json").read_text(encoding="utf-8"))
rig = rig_block["rigs"][0]

# sprites[] preload — uno por hueso que dibuja parte
sprites = []
for b in rig["bones"]:
    if not b.get("sprite"):
        continue
    bid = b["id"]
    sprites.append({
        "name": b["sprite"],
        "manifest_key": f"{RIG_DIR}/{bid}",
        "behavior": "preload",
        "params": {"high_res": True},
    })
    # copiar la parte al staging
    dst = STAGE / f"sprites/{RIG_DIR}/{bid}"
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy(RP / "parts" / bid / "frame_001.png", dst / "frame_001.png")

spec = {
    "id": SCENE_ID,
    "schema_version": 1,
    "type": "canvas_scene",
    "image_layers": [
        {"key": "bg", "url": "https://placeholder/bg.webp", "z": 0,
         "parallax_factor": 0.05, "scroll_factor": 0.0}
    ],
    "sprites": sprites,
    "rigs": [rig],
}
(STAGE / "scene_specs" / f"{SCENE_ID}.json").write_text(
    json.dumps(spec, indent=2, ensure_ascii=False), encoding="utf-8")

# fondo -> webp
bg = Image.open(CHAR / "fondo_limpio.png").convert("RGB")
bg.save(STAGE / f"scene_layers/{SCENE_ID}/bg.webp", "WEBP", quality=88, method=6)

# listado de archivos para el push
files = sorted(str(p.relative_to(STAGE)).replace("\\", "/") for p in STAGE.rglob("*") if p.is_file())
(STAGE / "_filelist.txt").write_text("\n".join(files), encoding="utf-8")
print(f"[OK] staging en {STAGE}")
print(f"  sprites preload: {len(sprites)}  ·  archivos: {len(files)}")
for f in files: print("   ", f)
