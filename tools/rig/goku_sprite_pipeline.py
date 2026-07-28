"""Pipeline para publicar (OCULTO) un canvas_scene con:
  - Goku nino como SPRITE de 4 frames (behavior:"static", fullscreen:true),
    interleaved por z con las image_layers de fondo con parallax.
  - fondo_limpio / esfera_siete_estrellas / nube_voladora como image_layers
    con parallax_factor distinto (profundidad) y scroll_factor=0 (Samsung
    bloquea onOffsetsChanged).

A diferencia de rig_codex_roots_pipeline.py (que arma bones[]+keyframes para
un rig de huesos), este contenido NO usa bones — Goku es UN sprite normal
con 4 PNGs full-canvas como frames de sprite sheet (loop de poses), igual
que goku_genkidama_orb o v160_sprites/dragon_main.

Formato verificado en:
  - android/.../scene/SceneSpec.kt (SpriteDef, ImageLayerDef)
  - android/.../scene/SpriteController.kt (StaticController: params
    fullscreen/z/parallax_factor/alpha; frame_skip = ticks por frame)
  - android/.../scene/CanvasSceneRenderer.kt (interleave sprites con
    params.z junto a image_layers, sorted por z ascendente)
  - lib/core/services/sprite_download_service.dart (ensureSpritesForScene
    lee sprites[].manifest_key contra wallpaper-sprites/manifest.json)

Uso:
  python goku_sprite_pipeline.py
"""
import io, json, re, sys, urllib.request, zipfile
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
PUB = f"{PROJECT}/storage/v1/object/public"
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]

CHAR = Path(r"G:\Mi unidad\pixoraIA_admin\ia_contenido_pipeline\wallpapers\1_por_editar\goku_nino_esfera_energia_rig_production")
PARTS = CHAR / "parts"

SID = "goku_nino_esfera_energia_rig_production"
TITLE_ES = "Goku niño: esfera de energía"
TITLE_EN = "Kid Goku: energy sphere"
TAGS = ["goku", "dragon ball", "anime", "energia", "accion"]
CATEGORY = "cultura"
W, H = 1080, 1920

# ── parallax / z (acordado con Eduardo) ──
BG_PF, BG_Z = 0.10, 0
ESFERA_PF, ESFERA_Z = 0.35, 10
GOKU_Z = 15          # entre esfera (detras) y nube (al frente)
GOKU_PF = 0.50        # igual a la nube: Goku esta parado en ella, deben moverse juntos
NUBE_PF, NUBE_Z = 0.50, 20

FRAME_SKIP = 45        # ~1.5s por pose @ ~33ms/tick (tier HIGH); ver duda en reporte
MANIFEST_KEY = f"canvas_sprites/{SID}/goku"


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


def webp_bytes(img, quality=90, lossless=False):
    b = io.BytesIO()
    img.save(b, "WEBP", quality=quality, method=6, lossless=lossless)
    return b.getvalue()


print(f"== procesando {SID} ({W}x{H}) sprite Goku (4 poses) + parallax layers ==")

bg_src = Image.open(CHAR / "fondo_limpio_1080x1920.png").convert("RGB")
esfera_src = Image.open(PARTS / "esfera_siete_estrellas.png").convert("RGBA")
nube_src = Image.open(PARTS / "nube_voladora.png").convert("RGBA")
pose_paths = [PARTS / f"goku_pose_0{i}.png" for i in range(1, 5)]
poses = [Image.open(p).convert("RGBA") for p in pose_paths]
flat_src = Image.open(CHAR / "wallpaper_estatico_1080x1920.png").convert("RGB")

for p, im in zip(pose_paths, poses):
    assert im.size == (W, H), f"{p.name} size {im.size} != {W}x{H}"
assert esfera_src.size == (W, H) and nube_src.size == (W, H) and bg_src.size == (W, H)

# ── recompose debug: bg -> esfera -> pose1 -> nube (mismo orden z que el spec) ──
recompose = bg_src.convert("RGBA").copy()
recompose.alpha_composite(esfera_src)
recompose.alpha_composite(poses[0])
recompose.alpha_composite(nube_src)
DBG = Path(r"C:/Users/lalo/Desktop/RIG_GOKU_REVISAR"); DBG.mkdir(exist_ok=True)
recompose_path = DBG / f"{SID}_recompose.png"
recompose.convert("RGB").save(recompose_path)

# ── spec ──
bg_layer = {"key": "bg", "url": f"{PUB}/wallpaper-images/{SID}_bg.webp",
            "z": BG_Z, "parallax_factor": BG_PF, "scroll_factor": 0.0, "scale": 1.0}
esfera_layer = {"key": "esfera", "url": f"{PUB}/wallpaper-images/{SID}_esfera.webp",
                 "z": ESFERA_Z, "parallax_factor": ESFERA_PF, "scroll_factor": 0.0, "scale": 1.0}
nube_layer = {"key": "nube", "url": f"{PUB}/wallpaper-images/{SID}_nube.webp",
              "z": NUBE_Z, "parallax_factor": NUBE_PF, "scroll_factor": 0.0, "scale": 1.0}

goku_sprite = {
    "name": "goku", "manifest_key": MANIFEST_KEY, "behavior": "static",
    "default_facing": "right",
    "params": {"fullscreen": True, "z": GOKU_Z, "parallax_factor": GOKU_PF, "alpha": 255},
    "frame_skip": FRAME_SKIP,
}

spec = {
    "id": SID, "schema_version": 1, "type": "canvas_scene",
    "title": {"es": TITLE_ES, "en": TITLE_EN}, "tags": TAGS, "category": CATEGORY,
    "featured": False, "published": False,
    "hidden_in": ["parallax_tab", CATEGORY, "daily", "events"],
    "background": {"url": f"{PUB}/wallpaper-images/{SID}_bg.webp",
                   "preview_url": f"{PUB}/wallpaper-images/{SID}_preview.webp", "scroll": False},
    "image_layers": [bg_layer, esfera_layer, nube_layer],
    "sprites": [goku_sprite],
}
(DBG / f"{SID}_spec.json").write_text(json.dumps(spec, indent=2, ensure_ascii=False), encoding="utf-8")

# ── 1) subir imagenes ──
print("== subiendo imagenes ==")
put("wallpaper-images", f"{SID}_bg.webp", webp_bytes(bg_src, quality=88), "image/webp")
put("wallpaper-images", f"{SID}_esfera.webp", webp_bytes(esfera_src, quality=90), "image/webp")
put("wallpaper-images", f"{SID}_nube.webp", webp_bytes(nube_src, quality=90), "image/webp")
put("wallpaper-images", f"{SID}.webp", webp_bytes(flat_src, quality=88), "image/webp")
pv = flat_src.copy(); pv.thumbnail((540, 1170), Image.LANCZOS)
put("wallpaper-images", f"{SID}_preview.webp", webp_bytes(pv, quality=85), "image/webp")

# ── 2) sprite ZIP (frame_001..frame_004.png) + manifest.json ──
print("== subiendo sprite ZIP ==")
zb = io.BytesIO()
with zipfile.ZipFile(zb, "w", zipfile.ZIP_DEFLATED) as zf:
    for i, im in enumerate(poses, start=1):
        fb = io.BytesIO(); im.save(fb, "PNG")
        zf.writestr(f"frame_{i:03d}.png", fb.getvalue())
zbytes = zb.getvalue()
zip_name = f"{SID}_goku.zip"
put("wallpaper-sprites", zip_name, zbytes, "application/zip")
manifest = get_json("wallpaper-sprites", "manifest.json") or {}
manifest[MANIFEST_KEY] = {"zip": zip_name, "frames": len(poses), "size": len(zbytes)}
put("wallpaper-sprites", "manifest.json", json.dumps(manifest, indent=2).encode("utf-8"), "application/json")

# ── 3) spec + catalog_index (oculto) ──
print("== publicando spec + catalog_index (oculto) ==")
put("wallpaper-scenes", f"{SID}.json", json.dumps(spec, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
idx = get_json("wallpaper-images", "catalog_index.json") or {"version": 0, "items": []}
entry = {"id": SID, "type": "canvas_scene", "schema": 1, "title": spec["title"],
         "preview_url": f"{PUB}/wallpaper-images/{SID}_preview.webp", "tags": TAGS,
         "category": CATEGORY, "featured": False, "spec_url": f"{PUB}/wallpaper-scenes/{SID}.json",
         "published": False, "hidden_in": spec["hidden_in"], "created_at": now_iso()}
idx["items"] = [it for it in idx.get("items", []) if it.get("id") != SID] + [entry]
idx["version"] = int(idx.get("version", 0)) + 1
idx["updated_at"] = now_iso()
put("wallpaper-images", "catalog_index.json", json.dumps(idx, ensure_ascii=False).encode("utf-8"), "application/json")

print(f"[OK] {SID} publicado OCULTO · sprite 4 frames · frame_skip={FRAME_SKIP} · idx v{idx['version']}")
print(f"recompose -> {recompose_path}")
