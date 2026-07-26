"""Publica el astronauta rig a Supabase, OCULTO (published:false). Mismo pipeline
que publish_heroina_rig.py: bg/flat/preview a wallpaper-images, 8 partes ZIP a
wallpaper-sprites + patch manifest, spec a wallpaper-scenes, entry en catalog_index.
El drift del fondo se agrega después (cuando el motor lo soporte).
"""
import io, json, re, sys, urllib.request, zipfile
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
PUB = f"{PROJECT}/storage/v1/object/public"
SID = "astronauta_nebula_flota"
CHAR = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/astronauta_nebula_rig_production")
STAGE = CHAR / "rig_out" / "device_staging"
RIG_DIR = "rigs/astronauta_v1"
PARTS = ["left_leg", "right_leg", "torso_tether", "left_upper_arm",
         "left_forearm_hand", "right_upper_arm", "right_forearm_hand", "helmet"]
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]

def now_iso(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def put(bucket, remote, body, ct):
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}", data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=120) as r: return r.status

def get_json(bucket, remote):
    try:
        return json.loads(urllib.request.urlopen(f"{PUB}/{bucket}/{remote}?nc={int(datetime.now().timestamp())}", timeout=20).read())
    except Exception:
        return None

print("== wallpaper-images (bg/flat/preview) ==")
put("wallpaper-images", f"{SID}_bg.webp", (STAGE / f"scene_layers/{SID}/bg.webp").read_bytes(), "image/webp")
flat = Image.open(STAGE / "master.webp").convert("RGB")
buf = io.BytesIO(); flat.save(buf, "WEBP", quality=88, method=6)
put("wallpaper-images", f"{SID}.webp", buf.getvalue(), "image/webp")
prev = flat.copy(); prev.thumbnail((540, 1170), Image.LANCZOS)
buf = io.BytesIO(); prev.save(buf, "WEBP", quality=85, method=6)
put("wallpaper-images", f"{SID}_preview.webp", buf.getvalue(), "image/webp")
print("  ✓ bg, flat, preview")

print("== wallpaper-sprites (8 partes) ==")
manifest = get_json("wallpaper-sprites", "manifest.json") or {}
for p in PARTS:
    png = (STAGE / f"sprites/{RIG_DIR}/{p}/frame_001.png").read_bytes()
    zbuf = io.BytesIO()
    with zipfile.ZipFile(zbuf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("frame_001.png", png)
    zb = zbuf.getvalue()
    zip_name = f"astronauta_v1_{p}.zip"
    put("wallpaper-sprites", zip_name, zb, "application/zip")
    manifest[f"{RIG_DIR}/{p}"] = {"zip": zip_name, "frames": 1, "size": len(zb)}
    print(f"  ✓ {zip_name}")
put("wallpaper-sprites", "manifest.json", json.dumps(manifest, indent=2).encode("utf-8"), "application/json")
print("  ✓ manifest patched")

print("== spec (published:false) ==")
spec = json.loads((STAGE / "scene_specs" / f"{SID}.json").read_text(encoding="utf-8"))
for lyr in spec["image_layers"]:
    if lyr["key"] == "bg": lyr["url"] = f"{PUB}/wallpaper-images/{SID}_bg.webp"
spec["title"] = {"es": "Astronauta a la deriva", "en": "Astronaut Adrift"}
spec["tags"] = ["espacio", "astronauta", "nasa", "rig", "nebula"]
spec["category"] = "cultura"
spec["featured"] = False
spec["published"] = False
spec["hidden_in"] = ["parallax_tab", "cultura", "daily", "events"]
spec["background"] = {"url": f"{PUB}/wallpaper-images/{SID}_bg.webp",
                      "preview_url": f"{PUB}/wallpaper-images/{SID}_preview.webp", "scroll": False}
put("wallpaper-scenes", f"{SID}.json", json.dumps(spec, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"  ✓ wallpaper-scenes/{SID}.json")

print("== catalog_index ==")
idx = get_json("wallpaper-images", "catalog_index.json") or {"version": 0, "items": []}
entry = {"id": SID, "type": "canvas_scene", "schema": 1, "title": spec["title"],
         "preview_url": f"{PUB}/wallpaper-images/{SID}_preview.webp", "tags": spec["tags"],
         "category": "cultura", "featured": False, "spec_url": f"{PUB}/wallpaper-scenes/{SID}.json",
         "published": False, "hidden_in": spec["hidden_in"], "created_at": now_iso()}
idx["items"] = [it for it in idx.get("items", []) if it.get("id") != SID] + [entry]
idx["version"] = int(idx.get("version", 0)) + 1
idx["updated_at"] = now_iso()
put("wallpaper-images", "catalog_index.json", json.dumps(idx, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"  ✓ catalog_index v{idx['version']}")
print(f"\n[OK] '{SID}' publicado OCULTO (8 huesos). Editable por ID en el editor.")
