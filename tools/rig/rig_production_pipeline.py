"""Pipeline genérico para rigs formato 'PRODUCTION' de Codex (partes full-canvas
+ RIG_SPEC_PRODUCTION.json + bbox_px + pivots normalizados). Hace TODO:
cropea partes a bbox, convierte a rigs[] de Pixora, agrega drift al fondo,
y publica OCULTO a Supabase.

Uso:
  python rig_production_pipeline.py <carpeta> <rig_dir> "<title_es>" "<title_en>" "<tags csv>" [bg_scale] [drift_json]

Ej:
  python rig_production_pipeline.py ".../delfines_santuario_rig_production" rigs/delfines_v1 \
    "Delfines: santuario de luz" "Dolphins: sanctuary of light" "oceano,delfines,mar,rig,animales" \
    1.25 '{"amp_x_pct":1.0,"amp_y_pct":-0.5,"scale_min":1.045,"scale_max":1.055,"rot_deg":0,"period_s":12}'
"""
import io, json, re, sys, urllib.request, zipfile, shutil
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
PUB = f"{PROJECT}/storage/v1/object/public"
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]

CHAR = Path(sys.argv[1])
RIG_DIR = sys.argv[2]                       # p.ej. rigs/delfines_v1
TITLE_ES = sys.argv[3]; TITLE_EN = sys.argv[4]
TAGS = [t.strip() for t in sys.argv[5].split(",") if t.strip()]
BG_SCALE = float(sys.argv[6]) if len(sys.argv) > 6 else 1.25
DRIFT = json.loads(sys.argv[7]) if len(sys.argv) > 7 else None

prod = json.loads((CHAR / "RIG_SPEC_PRODUCTION.json").read_text(encoding="utf-8"))
SID = prod["id"]
W = prod["canvas"]["width"]; H = prod["canvas"]["height"]
anim = next(iter(prod.get("animations", {}).values()), {})
tracks = anim.get("tracks", {})
loop_s = anim.get("duration_ms", 5600) / 1000.0

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

def find(*names):
    for n in names:
        if (CHAR / n).is_file(): return CHAR / n
    return None

# ── 1) cut partes + rig_block ──
print(f"== procesando {SID} ({W}x{H}, {len(prod['bones'])} bones) ==")
STAGE = CHAR / "rig_out" / "device_staging"
if STAGE.exists(): shutil.rmtree(STAGE)
(STAGE / "sprites" / RIG_DIR).mkdir(parents=True, exist_ok=True)
bones_out, sprites_out, parts = [], [], []
recompose = Image.new("RGBA", (W, H), (0, 0, 0, 0))
for b in sorted(prod["bones"], key=lambda x: x.get("z", 0)):
    bid = b["id"]
    bone = {"id": bid, "parent": b.get("parent"), "sprite": None,
            "pivot_px": [round(b["pivot"][0] * W), round(b["pivot"][1] * H)], "z": b.get("z", 0)}
    if bid in tracks: bone["keyframes"] = tracks[bid]
    if b.get("file"):
        bb = b["bbox_px"]; x, y, w, h = bb["x"], bb["y"], bb["w"], bb["h"]
        crop = Image.open(CHAR / b["file"]).convert("RGBA").crop((x, y, x + w, y + h))
        (STAGE / "sprites" / RIG_DIR / bid).mkdir(parents=True, exist_ok=True)
        crop.save(STAGE / "sprites" / RIG_DIR / bid / "frame_001.png")
        recompose.alpha_composite(crop, (x, y))
        bone["sprite"] = f"rig_{bid}"; bone["offset_px"] = [x, y]
        sprites_out.append({"name": f"rig_{bid}", "manifest_key": f"{RIG_DIR}/{bid}",
                            "behavior": "preload", "params": {"high_res": True}})
        parts.append(bid)
    bones_out.append(bone)
print(f"  {len(parts)} partes: {parts}")

bg_layer = {"key": "bg", "url": f"{PUB}/wallpaper-images/{SID}_bg.webp", "z": 0,
            "parallax_factor": 0.08, "scroll_factor": 0.0, "scale": BG_SCALE}
if DRIFT: bg_layer["drift"] = DRIFT
spec = {
    "id": SID, "schema_version": 1, "type": "canvas_scene",
    "title": {"es": TITLE_ES, "en": TITLE_EN}, "tags": TAGS, "category": "cultura",
    "featured": False, "published": False,
    "hidden_in": ["parallax_tab", "cultura", "daily", "events"],
    "background": {"url": f"{PUB}/wallpaper-images/{SID}_bg.webp",
                   "preview_url": f"{PUB}/wallpaper-images/{SID}_preview.webp", "scroll": False},
    "image_layers": [bg_layer],
    "sprites": sprites_out,
    "rigs": [{"name": SID.split("_")[0], "z": 10, "anchor": [0.5, 0.55],
              "char_size": [W, H], "scale": 1.0, "loop_seconds": loop_s,
              "easing": "smooth", "bones": bones_out}],
}

# recompose debug
DBG = Path(r"C:/Users/lalo/Desktop/RIG_HEROINA_REVISAR"); DBG.mkdir(exist_ok=True)
bgimg = Image.open(find(f"fondo_limpio_{W}x{H}.png", "fondo_limpio.png")).convert("RGBA").resize((W, H))
comp = bgimg.copy(); comp.alpha_composite(recompose)
comp.convert("RGB").save(DBG / f"{SID}_recompose.png")

# ── 2) publicar oculto ──
print("== publicando (oculto) ==")
bgsrc = find(f"fondo_limpio_{W}x{H}.png", "fondo_limpio.png")
b = io.BytesIO(); Image.open(bgsrc).convert("RGB").save(b, "WEBP", quality=88, method=6)
put("wallpaper-images", f"{SID}_bg.webp", b.getvalue(), "image/webp")
flat = Image.open(find(f"wallpaper_estatico_{W}x{H}.png", "wallpaper_master.png")).convert("RGB")
b = io.BytesIO(); flat.save(b, "WEBP", quality=88, method=6); put("wallpaper-images", f"{SID}.webp", b.getvalue(), "image/webp")
pv = flat.copy(); pv.thumbnail((540, 1170), Image.LANCZOS)
b = io.BytesIO(); pv.save(b, "WEBP", quality=85, method=6); put("wallpaper-images", f"{SID}_preview.webp", b.getvalue(), "image/webp")
manifest = get_json("wallpaper-sprites", "manifest.json") or {}
short = RIG_DIR.split("/")[-1]
for p in parts:
    png = (STAGE / "sprites" / RIG_DIR / p / "frame_001.png").read_bytes()
    zb = io.BytesIO()
    with zipfile.ZipFile(zb, "w", zipfile.ZIP_DEFLATED) as zf: zf.writestr("frame_001.png", png)
    zbytes = zb.getvalue(); zn = f"{short}_{p}.zip"
    put("wallpaper-sprites", zn, zbytes, "application/zip")
    manifest[f"{RIG_DIR}/{p}"] = {"zip": zn, "frames": 1, "size": len(zbytes)}
put("wallpaper-sprites", "manifest.json", json.dumps(manifest, indent=2).encode("utf-8"), "application/json")
put("wallpaper-scenes", f"{SID}.json", json.dumps(spec, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
idx = get_json("wallpaper-images", "catalog_index.json") or {"version": 0, "items": []}
entry = {"id": SID, "type": "canvas_scene", "schema": 1, "title": spec["title"],
         "preview_url": f"{PUB}/wallpaper-images/{SID}_preview.webp", "tags": TAGS,
         "category": "cultura", "featured": False, "spec_url": f"{PUB}/wallpaper-scenes/{SID}.json",
         "published": False, "hidden_in": spec["hidden_in"], "created_at": now_iso()}
idx["items"] = [it for it in idx.get("items", []) if it.get("id") != SID] + [entry]
idx["version"] = int(idx.get("version", 0)) + 1; idx["updated_at"] = now_iso()
put("wallpaper-images", "catalog_index.json", json.dumps(idx, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"[OK] {SID} publicado OCULTO · {len(parts)} partes · drift={'sí' if DRIFT else 'no'} · idx v{idx['version']}")
print(f"recompose -> {DBG/(SID+'_recompose.png')}")
