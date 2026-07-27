"""Pipeline para el NUEVO formato de rig de Codex ('roots' + 'layers' +
'animation' con rotationDeg/translatePx arrays de 3 valores), distinto al
formato 'bones'+'tracks' de rig_production_pipeline.py.

Convierte a bones[]+keyframes de Pixora, respetando la jerarquia:
    scene_root (centro, sin anim)
      +- titan_root  (pivote = centro del titan, keyframes del titan)
      |    +- titan_* (partes con sprite + keyframes propios)
      +- levi_root   (pivote = centro de Levi, keyframes AMORTIGUADOS)
           +- levi_*  (partes con sprite + keyframes propios, rot amortiguada)

El damp de levi_root evita que Levi se separe del coloso con el movimiento.
Agrega drift suave al fondo y publica OCULTO a Supabase.

Uso:
  python rig_codex_roots_pipeline.py <carpeta> <rig_dir> "<title_es>" "<title_en>" "<tags csv>" [category]
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
RIG_DIR = sys.argv[2]                       # p.ej. rigs/levi_v1
TITLE_ES = sys.argv[3]; TITLE_EN = sys.argv[4]
TAGS = [t.strip() for t in sys.argv[5].split(",") if t.strip()]
CATEGORY = sys.argv[6] if len(sys.argv) > 6 else "cultura"

# ── Ajustes anti-separacion de Levi (pedido de Eduardo) ──
LEVI_ROOT_DAMP = 0.40   # translate + rot del grupo Levi (lo que lo separa del titan)
LEVI_PART_DAMP = 0.60   # rot de las partes internas de Levi (capa/hojas: conservar vida)

# drift suave del fondo (murallas, movimiento lento)
DRIFT = {"amp_x_pct": 1.4, "amp_y_pct": -0.7, "scale_min": 1.040,
         "scale_max": 1.060, "rot_deg": 0.0, "period_s": 16}
BG_SCALE = 1.22

prod = json.loads((CHAR / "RIG_SPEC_PRODUCTION.json").read_text(encoding="utf-8"))
report = json.loads((CHAR / "PARTS_REPORT.json").read_text(encoding="utf-8"))
SID = prod["id"]
W = prod["canvas"]["width"]; H = prod["canvas"]["height"]
loop_s = prod.get("loop", {}).get("durationMs", 6000) / 1000.0
anim = prod.get("animation", {})
bounds = {p["id"]: p["alphaBounds"] for p in report["parts"]}   # [x0,y0,x1,y1]

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

def union_center(prefix):
    xs0, ys0, xs1, ys1 = [], [], [], []
    for pid, b in bounds.items():
        if pid.startswith(prefix):
            xs0.append(b[0]); ys0.append(b[1]); xs1.append(b[2]); ys1.append(b[3])
    if not xs0: return [W / 2.0, H / 2.0]
    return [round((min(xs0) + max(xs1)) / 2.0), round((min(ys0) + max(ys1)) / 2.0)]

def kf_from_anim(bid, damp_xy=1.0, damp_rot=1.0):
    """rotationDeg [a,b,c] + translatePx [[x,y]x3] -> keyframes {t,x,y,rotation}."""
    a = anim.get(bid)
    if not a: return []
    rot = a.get("rotationDeg", [0, 0, 0])
    tr = a.get("translatePx", [[0, 0]] * len(rot))
    n = max(len(rot), len(tr))
    ts = [i / (n - 1) for i in range(n)] if n > 1 else [0.0]
    out = []
    for i in range(n):
        r = rot[i] if i < len(rot) else 0.0
        x, y = (tr[i] if i < len(tr) else [0, 0])
        out.append({"t": round(ts[i], 4),
                    "x": round(x * damp_xy, 3), "y": round(y * damp_xy, 3),
                    "rotation": round(r * damp_rot, 4), "scale": 1.0})
    return out

# ── 1) construir bones + cortar partes ──
print(f"== procesando {SID} ({W}x{H}) formato roots/layers ==")
STAGE = CHAR / "rig_out" / "device_staging"
if STAGE.exists(): shutil.rmtree(STAGE)
(STAGE / "sprites" / RIG_DIR).mkdir(parents=True, exist_ok=True)

bones, sprites_out, parts = [], [], []
# roots virtuales
bones.append({"id": "scene_root", "parent": None, "sprite": None,
              "pivot_px": [round(W / 2), round(H / 2)], "z": 0, "keyframes": []})
bones.append({"id": "titan_root", "parent": "scene_root", "sprite": None,
              "pivot_px": union_center("titan_"), "z": 0,
              "keyframes": kf_from_anim("titan_root")})
bones.append({"id": "levi_root", "parent": "scene_root", "sprite": None,
              "pivot_px": union_center("levi_"), "z": 0,
              "keyframes": kf_from_anim("levi_root", LEVI_ROOT_DAMP, LEVI_ROOT_DAMP)})
print(f"  titan_root pivot={union_center('titan_')}  levi_root pivot={union_center('levi_')}  (levi damp {LEVI_ROOT_DAMP})")

recompose = Image.new("RGBA", (W, H), (0, 0, 0, 0))
for layer in sorted(prod["layers"], key=lambda x: x.get("z", 0)):
    lid = layer["id"]
    is_levi = lid.startswith("levi_")
    src = Image.open(CHAR / layer["asset"]).convert("RGBA")
    x0, y0, x1, y1 = bounds.get(lid, [0, 0, W, H])
    crop = src.crop((x0, y0, x1, y1))
    (STAGE / "sprites" / RIG_DIR / lid).mkdir(parents=True, exist_ok=True)
    crop.save(STAGE / "sprites" / RIG_DIR / lid / "frame_001.png")
    recompose.alpha_composite(crop, (x0, y0))
    pn = layer["pivotNormalized"]
    kf = kf_from_anim(lid, 1.0, LEVI_PART_DAMP if is_levi else 1.0)
    bones.append({"id": lid, "parent": layer["parent"], "sprite": f"rig_{lid}",
                  "pivot_px": [round(pn[0] * W), round(pn[1] * H)],
                  "offset_px": [x0, y0], "z": layer.get("z", 0), "keyframes": kf})
    sprites_out.append({"name": f"rig_{lid}", "manifest_key": f"{RIG_DIR}/{lid}",
                        "behavior": "preload", "params": {"high_res": True}})
    parts.append(lid)
print(f"  {len(parts)} partes: {parts}")

bg_layer = {"key": "bg", "url": f"{PUB}/wallpaper-images/{SID}_bg.webp", "z": 0,
            "parallax_factor": 0.08, "scroll_factor": 0.0, "scale": BG_SCALE, "drift": DRIFT}
spec = {
    "id": SID, "schema_version": 1, "type": "canvas_scene",
    "title": {"es": TITLE_ES, "en": TITLE_EN}, "tags": TAGS, "category": CATEGORY,
    "featured": False, "published": False,
    "hidden_in": ["parallax_tab", CATEGORY, "daily", "events"],
    "background": {"url": f"{PUB}/wallpaper-images/{SID}_bg.webp",
                   "preview_url": f"{PUB}/wallpaper-images/{SID}_preview.webp", "scroll": False},
    "image_layers": [bg_layer],
    "sprites": sprites_out,
    "rigs": [{"name": "levi", "z": 10, "anchor": [0.5, 0.55],
              "char_size": [W, H], "scale": 1.0, "loop_seconds": loop_s,
              "easing": "smooth", "bones": bones}],
}

# recompose debug
DBG = Path(r"C:/Users/lalo/Desktop/RIG_LEVI_REVISAR"); DBG.mkdir(exist_ok=True)
bgimg = Image.open(find(f"fondo_limpio_{W}x{H}.png", "fondo_limpio.png")).convert("RGBA").resize((W, H))
comp = bgimg.copy(); comp.alpha_composite(recompose)
comp.convert("RGB").save(DBG / f"{SID}_recompose.png")
(DBG / f"{SID}_spec.json").write_text(json.dumps(spec, indent=2, ensure_ascii=False), encoding="utf-8")

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
         "category": CATEGORY, "featured": False, "spec_url": f"{PUB}/wallpaper-scenes/{SID}.json",
         "published": False, "hidden_in": spec["hidden_in"], "created_at": now_iso()}
idx["items"] = [it for it in idx.get("items", []) if it.get("id") != SID] + [entry]
idx["version"] = int(idx.get("version", 0)) + 1; idx["updated_at"] = now_iso()
put("wallpaper-images", "catalog_index.json", json.dumps(idx, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"[OK] {SID} publicado OCULTO · {len(parts)} partes · idx v{idx['version']}")
print(f"recompose -> {DBG/(SID+'_recompose.png')}")
