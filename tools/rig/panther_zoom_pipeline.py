"""Pipeline para la pantera bioluminiscente (formato Codex roots/layers) CON
pre-zoom coherente al rostro (opción B, factor 1.55 centrado en el rostro).

Re-encuadra TODAS las imagenes (fondo + partes) con el mismo crop, transforma
pivotes normalizados y keyframes por la afin del zoom, regenera los bounds
(alpha bbox real de cada parte recortada) y publica OCULTO a Supabase.

No depende de PARTS_REPORT (lo regenera) — tolera el formato de este arte.
Efectos avanzados (eyeGlow, ripples, fireflies...) NO se portan: el rig solo
mueve partes. reflejo/agua que queden fuera del crop se descartan.

Uso: python panther_zoom_pipeline.py
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

CHAR = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/pantera_bioluminiscente_rig_production_v2")
RIG_DIR = "rigs/pantera_v1"
TITLE_ES = "Pantera bioluminiscente"
TITLE_EN = "Bioluminescent panther"
TAGS = ["pantera", "felino", "bioluminiscente", "noche", "agua", "rig", "animales"]
CATEGORY = "cultura"

# ── Zoom opción B (aprobada por Eduardo): rostro protagonista ──
ZOOM = 1.55
FOCUS = (560, 830)   # centro del rostro en el canvas original

DRIFT = {"amp_x_pct": 1.0, "amp_y_pct": -0.6, "scale_min": 1.03,
         "scale_max": 1.05, "rot_deg": 0.0, "period_s": 14}
BG_SCALE = 1.20

prod = json.loads((CHAR / "RIG_SPEC_PRODUCTION.json").read_text(encoding="utf-8"))
SID = prod["id"]
W = prod["canvas"]["width"]; H = prod["canvas"]["height"]
loop_s = prod.get("loop", {}).get("durationMs", 7200) / 1000.0
anim = prod.get("animation", {})

# crop rect de la afin
cw = W / ZOOM; ch = H / ZOOM
x0 = max(0.0, min(W - cw, FOCUS[0] - cw / 2))
y0 = max(0.0, min(H - ch, FOCUS[1] - ch / 2))
CROP = (int(round(x0)), int(round(y0)), int(round(x0 + cw)), int(round(y0 + ch)))
fx = W / cw; fy = H / ch   # factores efectivos (== ZOOM)

def tpx(px, py):
    """punto original -> nuevo canvas (post-zoom)."""
    return (px - x0) * fx, (py - y0) * fy

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

def rezoom(img):
    """crop al rect de la opcion B + resize a canvas completo."""
    return img.convert("RGBA").resize((W, H), Image.LANCZOS, box=CROP)

def kf_from_anim(bid):
    """rotationDeg/translatePx/scale -> keyframes {t,x,y,rotation,scale}. translate se escala por el zoom."""
    a = anim.get(bid)
    if not a: return []
    rot = a.get("rotationDeg"); tr = a.get("translatePx"); sc = a.get("scale")
    n = max(len(rot) if rot else 0, len(tr) if tr else 0, len(sc) if sc else 0, 0)
    if n == 0: return []
    ts = [i / (n - 1) for i in range(n)] if n > 1 else [0.0]
    out = []
    for i in range(n):
        r = rot[i] if rot and i < len(rot) else 0.0
        x, y = (tr[i] if tr and i < len(tr) else [0, 0])
        s = sc[i] if sc and i < len(sc) else 1.0
        out.append({"t": round(ts[i], 4), "x": round(x * fx, 3), "y": round(y * fy, 3),
                    "rotation": round(r, 4), "scale": round(s, 4)})
    return out

print(f"== {SID} · zoom {ZOOM}x foco {FOCUS} · crop {CROP} ==")
STAGE = CHAR / "rig_out" / "device_staging"
if STAGE.exists(): shutil.rmtree(STAGE)
(STAGE / "sprites" / RIG_DIR).mkdir(parents=True, exist_ok=True)

# roots virtuales
bones = [{"id": "scene_root", "parent": None, "sprite": None,
          "pivot_px": [round(W / 2), round(H / 2)], "z": 0, "keyframes": []}]
for rid in ("panther_root", "water_root"):
    a = anim.get(rid)
    bones.append({"id": rid, "parent": "scene_root", "sprite": None,
                  "pivot_px": [round(W / 2), round(H / 2)], "z": 0,
                  "keyframes": kf_from_anim(rid) if a else []})

sprites_out, parts, recompose = [], [], Image.new("RGBA", (W, H), (0, 0, 0, 0))
for layer in sorted(prod["layers"], key=lambda x: x.get("z", 0)):
    lid = layer["id"]
    src = rezoom(Image.open(CHAR / layer["asset"]))   # parte re-encuadrada, full canvas
    bbox = src.getbbox()
    if not bbox:
        print(f"  · {lid}: vacío tras el zoom (fuera de encuadre) — descartado")
        continue
    x0b, y0b, x1b, y1b = bbox
    crop = src.crop(bbox)
    (STAGE / "sprites" / RIG_DIR / lid).mkdir(parents=True, exist_ok=True)
    crop.save(STAGE / "sprites" / RIG_DIR / lid / "frame_001.png")
    recompose.alpha_composite(crop, (x0b, y0b))
    pn = layer["pivotNormalized"]
    nx, ny = tpx(pn[0] * W, pn[1] * H)   # pivote transformado al nuevo canvas
    bones.append({"id": lid, "parent": layer["parent"], "sprite": f"rig_{lid}",
                  "pivot_px": [round(nx), round(ny)], "offset_px": [x0b, y0b],
                  "z": layer.get("z", 0), "keyframes": kf_from_anim(lid)})
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
    "image_layers": [bg_layer], "sprites": sprites_out,
    "rigs": [{"name": "pantera", "z": 10, "anchor": [0.5, 0.55],
              "char_size": [W, H], "scale": 1.0, "loop_seconds": loop_s,
              "easing": "smooth", "bones": bones}],
}

DBG = Path(r"C:/Users/lalo/Desktop/RIG_PANTERA_REVISAR"); DBG.mkdir(exist_ok=True)
bg_zoomed = rezoom(Image.open(find(f"fondo_limpio_{W}x{H}.png", "fondo_limpio.png")))
comp = bg_zoomed.copy(); comp.alpha_composite(recompose)
comp.convert("RGB").save(DBG / f"{SID}_recompose.png")

# ── publicar oculto ──
print("== publicando (oculto) ==")
b = io.BytesIO(); bg_zoomed.convert("RGB").save(b, "WEBP", quality=88, method=6)
put("wallpaper-images", f"{SID}_bg.webp", b.getvalue(), "image/webp")
flat = rezoom(Image.open(find(f"wallpaper_estatico_{W}x{H}.png", "wallpaper_master.png"))).convert("RGB")
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
print(f"[OK] {SID} publicado OCULTO · {len(parts)} partes · zoom {ZOOM}x · idx v{idx['version']}")
print(f"recompose -> {DBG/(SID+'_recompose.png')}")
