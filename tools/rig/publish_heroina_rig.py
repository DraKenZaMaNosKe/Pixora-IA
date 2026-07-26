"""Publica la escena rig 'heroina_candy_mecha_rig_v1' a Supabase, OCULTA para
testers (published:false). Sube: bg + flat + preview (wallpaper-images),
5 partes como ZIP (wallpaper-sprites) + patch manifest.json, spec
(wallpaper-scenes), y upsert en catalog_index.json con published:false.

Para hacerla VISIBLE luego: cambiar published a true en el spec y el índice
(o usar /api/scene-visibility) + FCM.
"""
import io, json, re, sys, urllib.request, zipfile
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
PUB = f"{PROJECT}/storage/v1/object/public"
SID = "heroina_candy_mecha_rig_v1"
CHAR = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/heroina_candy_mecha_rig_v1")
STAGE = CHAR / "rig_parts" / "device_staging"
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
    url = f"{PUB}/{bucket}/{remote}?nc={int(datetime.now().timestamp())}"
    try:
        return json.loads(urllib.request.urlopen(url, timeout=20).read())
    except Exception:
        return None

# ── 1) bg + flat + preview a wallpaper-images ──
print("== assets a wallpaper-images ==")
bg = (STAGE / "scene_layers" / SID / "bg.webp").read_bytes()
put("wallpaper-images", f"{SID}_bg.webp", bg, "image/webp")
print(f"  ✓ {SID}_bg.webp")

flat_src = Image.open(CHAR / "wallpaper_master.png").convert("RGB")
buf = io.BytesIO(); flat_src.save(buf, "WEBP", quality=88, method=6)
put("wallpaper-images", f"{SID}.webp", buf.getvalue(), "image/webp")
print(f"  ✓ {SID}.webp (flat)")

prev = flat_src.copy(); prev.thumbnail((540, 1170), Image.LANCZOS)
buf = io.BytesIO(); prev.save(buf, "WEBP", quality=85, method=6)
put("wallpaper-images", f"{SID}_preview.webp", buf.getvalue(), "image/webp")
print(f"  ✓ {SID}_preview.webp")

# ── 2) partes como ZIP a wallpaper-sprites + patch manifest ──
print("== sprites a wallpaper-sprites ==")
parts = ["arm", "head", "leg_bent", "leg_up", "torso"]
manifest = get_json("wallpaper-sprites", "manifest.json") or {}
for p in parts:
    png = (STAGE / "sprites" / "rigs" / "heroina_v1" / p / "frame_001.png").read_bytes()
    zbuf = io.BytesIO()
    with zipfile.ZipFile(zbuf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("frame_001.png", png)
    zbytes = zbuf.getvalue()
    zip_name = f"heroina_v1_{p}.zip"
    put("wallpaper-sprites", zip_name, zbytes, "application/zip")
    manifest_key = f"rigs/heroina_v1/{p}"
    manifest[manifest_key] = {"zip": zip_name, "frames": 1, "size": len(zbytes)}
    print(f"  ✓ {zip_name}  key={manifest_key}")
put("wallpaper-sprites", "manifest.json",
    json.dumps(manifest, indent=2).encode("utf-8"), "application/json")
print("  ✓ manifest.json patched")

# ── 3) spec a wallpaper-scenes (published:false, hidden) ──
print("== spec a wallpaper-scenes ==")
spec = json.loads((STAGE / "scene_specs" / f"{SID}.json").read_text(encoding="utf-8"))
# url real del layer bg
for lyr in spec.get("image_layers", []):
    if lyr.get("key") == "bg":
        lyr["url"] = f"{PUB}/wallpaper-images/{SID}_bg.webp"
spec["title"] = {"es": "Heroína Candy Mecha", "en": "Candy Mecha Heroine"}
spec["tags"] = ["anime", "mecha", "candy", "rig"]
spec["category"] = "cultura"
spec["featured"] = False
spec["published"] = False           # ← OCULTA para testers
spec["hidden_in"] = ["parallax_tab", "cultura", "daily", "events"]
spec["background"] = {"url": f"{PUB}/wallpaper-images/{SID}_bg.webp",
                      "preview_url": f"{PUB}/wallpaper-images/{SID}_preview.webp",
                      "scroll": False}
put("wallpaper-scenes", f"{SID}.json",
    json.dumps(spec, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"  ✓ wallpaper-scenes/{SID}.json (published:false)")

# ── 4) catalog_index upsert (published:false → cliente lo filtra) ──
print("== catalog_index ==")
idx = get_json("wallpaper-images", "catalog_index.json") or {"version": 0, "items": []}
entry = {
    "id": SID, "type": "canvas_scene", "schema": 1,
    "title": spec["title"], "preview_url": f"{PUB}/wallpaper-images/{SID}_preview.webp",
    "tags": spec["tags"], "category": "cultura", "featured": False,
    "spec_url": f"{PUB}/wallpaper-scenes/{SID}.json",
    "published": False, "hidden_in": spec["hidden_in"], "created_at": now_iso(),
}
items = [it for it in idx.get("items", []) if it.get("id") != SID]
items.append(entry)
idx["items"] = items
idx["version"] = int(idx.get("version", 0)) + 1
idx["updated_at"] = now_iso()
put("wallpaper-images", "catalog_index.json",
    json.dumps(idx, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"  ✓ catalog_index.json v{idx['version']} (entry published:false)")

print(f"\n[OK] '{SID}' publicada OCULTA. Testers NO la ven. Editable por id en el editor.")
print("Para hacerla visible: cambiar published->true en spec + índice (o /api/scene-visibility).")
