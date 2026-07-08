"""Upload Ariel · La Sirenita — static + canvas_scene (3D LIVE) with a
2-frame swimming sprite for the character.

Unlike Marina (single baked subject), here Ariel's whole body IS the animated
sprite: it cycles between two swim poses (pose_01 <-> pose_02) so she looks
like she's gently swimming. Same sprite pipeline as morrigan_cabello, but the
sprite is the full character (not an add-on layer), so image_layers = [fondo]
only and sprites = [ariel].

Assets in C:/Users/lalo/Desktop/wallPapers_repo/nuevos/ariel/:
  - solofondo_ariel.png            (1080x1920 underwater background, opaque)
  - ariel_nadando_pose_01.png      (1080x1920 transparent, swim frame A)
  - ariel_andando_pose_02.png      (1080x1920 transparent, swim frame B)
  - ariel_wallpaper_estatico.png   (1080x1920 composited flat -> static + preview)

The user will fine-tune the sprite position in the sprite editor afterwards.
If the 2-frame animation looks choppy, we drop the sprite and keep a single
pose as a static image_layer instead.
"""
import io
import json
import re
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
SPR_BUCKET = "wallpaper-sprites"
MANIFEST_KEY = "manifest.json"
TARGET = (1080, 2340)
SRC_SIZE = (1080, 1920)

SCENE_ID = "ariel_sirenita"
STATIC_ID = "ariel_sirenita_static"
SPRITE_NAME = "ariel"
SPRITE_MANIFEST_KEY = "ariel_nadando"
SPRITE_ZIP_NAME = "ariel_nadando.zip"

# Cycle order: pose_01 -> pose_02 -> loop
FRAME_FILES = ["ariel_nadando_pose_01.png", "ariel_andando_pose_02.png"]
CROP_PAD = 8
# 2 frames alternating; slow enough to read as a swim, not a flicker.
# 42 ticks @60Hz ~= 0.7s per pose.
FRAME_SKIP = 42

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/ariel")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_ariel")

SK = re.findall(
    r"eyJ[A-Za-z0-9_\-\.]{100,500}",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
)[0]

TITLE = {"es": "Ariel · La Sirenita", "en": "Ariel · The Little Mermaid"}
TAGS = ["ariel", "sirenita", "little_mermaid", "disney", "princesa",
        "oceano", "underwater", "3d", "parallax"]
STATIC_TAGS = ["ariel", "sirenita", "little_mermaid", "disney", "princesa", "oceano"]
GLOW = "#2FBFA8"

DESC_PLAIN = ("Ariel, la joven sirena de cabello rojo, explora los arrecifes de "
              "colores mientras la luz del sol se filtra desde la superficie. "
              "Hija del rey Triton, sonia con el mundo de arriba.")
DESC_RICH = ("[[name:Ariel]], la joven [[power:sirena]] de cabello rojo, explora los "
             "[[place:arrecifes de colores]] mientras la luz del sol se filtra desde la "
             "superficie. Hija del rey [[name:Triton]], sonia con el "
             "[[emotion:mundo de arriba]].")


# ============================================================
# Storage helpers
# ============================================================
def put(bucket, remote, body, ct="image/webp"):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}", data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("apikey", SK)
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"    PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def put_json(bucket, remote, data):
    put(bucket, remote, json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8"),
        "application/json")


def get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}?t=999"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def cover_fit_rgb(img, target=TARGET):
    tw, th = target
    src = img.convert("RGBA")
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(round(sw * scale)), int(round(sh * scale))
    resized = src.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    cropped = resized.crop((left, top, left + tw, top + th))
    out = Image.new("RGB", target, (0, 0, 0))
    out.paste(cropped, mask=cropped.split()[3])
    return out


def encode_webp(img, out_path, quality=90):
    img.save(out_path, "WEBP", quality=quality, method=6)
    return out_path.read_bytes()


# ============================================================
print("=" * 60)
print("Upload Ariel · La Sirenita — static + canvas_scene (2-frame swim)")
print("=" * 60)

if WORK.exists():
    shutil.rmtree(WORK)
WORK.mkdir(parents=True)

# ---- 1. Background + flat + preview -------------------------------
print("\n[1/6] Baking background + flat + preview...")
fondo_img = cover_fit_rgb(Image.open(SRC / "solofondo_ariel.png"))
fondo_body = encode_webp(fondo_img, WORK / f"{SCENE_ID}_fondo.webp", quality=90)

flat_img = cover_fit_rgb(Image.open(SRC / "ariel_wallpaper_estatico.png"))
flat_body = encode_webp(flat_img, WORK / f"{SCENE_ID}.webp", quality=88)
prev = flat_img.copy()
prev.thumbnail((540, 1170), Image.LANCZOS)
prev_body = encode_webp(prev, WORK / f"{SCENE_ID}_preview.webp", quality=85)

# ---- 2. Shared bbox across the 2 swim frames ----------------------
print("[2/6] Computing shared bbox across swim frames...")
xs_min, xs_max = float("inf"), 0
ys_min, ys_max = float("inf"), 0
frames_rgba = []
for f in FRAME_FILES:
    im = Image.open(SRC / f).convert("RGBA")
    frames_rgba.append(im)
    a = np.array(im)[:, :, 3]
    ys, xs = np.where(a > 30)
    xs_min = min(xs_min, xs.min()); xs_max = max(xs_max, xs.max())
    ys_min = min(ys_min, ys.min()); ys_max = max(ys_max, ys.max())
sw, sh = SRC_SIZE
bl = max(0, int(xs_min) - CROP_PAD)
bt = max(0, int(ys_min) - CROP_PAD)
br = min(sw, int(xs_max) + CROP_PAD + 1)
bb = min(sh, int(ys_max) + CROP_PAD + 1)
crop_w, crop_h = br - bl, bb - bt
print(f"      bbox x=[{bl}..{br}] y=[{bt}..{bb}] -> {crop_w}x{crop_h}")

# ---- 3. Position + scale on TARGET (cover-fit math) ---------------
# Static is cover_fit of the 1080x1920 source into 1080x2340.
COVER = max(TARGET[0] / sw, TARGET[1] / sh)          # 2340/1920 = 1.21875
crop_left = (sw * COVER - TARGET[0]) / 2.0            # horizontal crop offset
crop_top = (sh * COVER - TARGET[1]) / 2.0            # 0 here (exact vertical)
cx_src = (bl + br) / 2.0
cy_src = (bt + bb) / 2.0
norm_x = round((cx_src * COVER - crop_left) / TARGET[0], 4)
norm_y = round((cy_src * COVER - crop_top) / TARGET[1], 4)
# high_res -> decW = crop_w. rw = crop_w * scale * surfaceW(1080).
# Want rw = crop_w * COVER (same on-screen size as the static). => scale=COVER/1080
sprite_scale = round(COVER / 1080.0, 6)
print(f"      sprite anchor norm x={norm_x} y={norm_y}  scale={sprite_scale}")

# ---- 4. Crop frames + build ZIP -----------------------------------
print(f"[3/6] Cropping {len(FRAME_FILES)} frames + zipping...")
zip_buf = io.BytesIO()
with zipfile.ZipFile(zip_buf, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    for i, im in enumerate(frames_rgba):
        cropped = im.crop((bl, bt, br, bb))
        b = io.BytesIO()
        cropped.save(b, "PNG", optimize=True)
        zf.writestr(f"frame_{i:03d}.png", b.getvalue())
zip_bytes = zip_buf.getvalue()
print(f"      {SPRITE_ZIP_NAME}: {len(FRAME_FILES)} frames zip={len(zip_bytes):,} B")

# ---- 5. Upload everything -----------------------------------------
print("[4/6] Uploading to Storage...")
put(IMG_BUCKET, f"{SCENE_ID}_fondo.webp", fondo_body)
put(IMG_BUCKET, f"{SCENE_ID}.webp", flat_body)
put(IMG_BUCKET, f"{SCENE_ID}_preview.webp", prev_body)
put(IMG_BUCKET, f"{STATIC_ID}.webp", flat_body)
put(IMG_BUCKET, f"{STATIC_ID}_preview.webp", prev_body)
put(SPR_BUCKET, SPRITE_ZIP_NAME, zip_bytes, "application/zip")

manifest = get_json(SPR_BUCKET, MANIFEST_KEY)
manifest[SPRITE_MANIFEST_KEY] = {"zip": SPRITE_ZIP_NAME,
                                 "frames": len(FRAME_FILES), "size": len(zip_bytes)}
put_json(SPR_BUCKET, MANIFEST_KEY, manifest)
print(f"      manifest entry: {SPRITE_MANIFEST_KEY}")

# ---- 6. Spec + catalog_index + Postgres ---------------------------
print("[5/6] Building spec + catalog_index...")
url_bg = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}_fondo.webp"
url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}.webp"
url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}_preview.webp"

spec = {
    "schema_version": 1,
    "id": SCENE_ID,
    "type": "canvas_scene",
    "title": TITLE,
    "tags": TAGS,
    "category": "disney",
    "featured": True,
    "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
    "image_layers": [
        {"key": "fondo", "url": url_bg, "z": 0,
         "parallax_factor": 0.0, "scroll_factor": 0.0, "scale": 1.22,
         "offset_x_px": 0, "offset_y_px": 0, "revision": 1},
    ],
    "sprites": [
        {"name": SPRITE_NAME, "manifest_key": SPRITE_MANIFEST_KEY,
         "behavior": "static", "frame_skip": FRAME_SKIP,
         "params": {"x": norm_x, "y": norm_y, "scale": sprite_scale,
                    "alpha": 255, "parallax_factor": 0.85, "high_res": True}},
    ],
    "particles": [],
    "events": [],
}
put_json(SCENES_BUCKET, f"{SCENE_ID}.json", spec)

try:
    cat = get_json(IMG_BUCKET, "catalog_index.json")
except Exception:
    cat = {"version": 0, "items": []}
cat["version"] = (cat.get("version", 0) or 0) + 1
entry = {
    "id": SCENE_ID, "type": "canvas_scene", "schema": 1, "title": TITLE,
    "preview_url": url_prev, "image_url": url_flat, "tags": TAGS,
    "category": "disney", "featured": True,
    "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{SCENE_ID}.json",
}
items = [it for it in cat.get("items", []) if it.get("id") != SCENE_ID]
items.insert(0, entry)
cat["items"] = items
put_json(IMG_BUCKET, "catalog_index.json", cat)

print("[6/6] Registering in Postgres...")
conn = connect()
cur = conn.cursor()
cur.execute("DELETE FROM wallpapers WHERE id IN (%s, %s);", (SCENE_ID, STATIC_ID))
print(f"    deleted {cur.rowcount} old rows")

# Scene -> SCENES category (shows in 3D LIVE)
cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
sort = cur.fetchone()[0]
cur.execute(
    """
    INSERT INTO wallpapers (
        id, name, description, description_rich, type, category, tags,
        image_path, preview_path, image_size, preview_size,
        glow_color, badge, sort_order, featured, trending_score,
        published, daily_eligible, author_name, media_width, media_height
    ) VALUES (
        %s, %s, %s, %s, 'static'::wallpaper_type, 'SCENES'::wallpaper_category, %s,
        %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, true, 0,
        true, false, %s, %s, %s
    ) RETURNING id;
    """,
    (SCENE_ID, "Ariel · La Sirenita", DESC_PLAIN, DESC_RICH, TAGS,
     f"{SCENE_ID}.webp", f"{SCENE_ID}_preview.webp", len(flat_body), len(prev_body),
     GLOW, sort, "Pixora Studio", TARGET[0], TARGET[1]),
)
print(f"    scene: {cur.fetchone()[0]}")

# Static -> WALLPAPERS category, clean tags, not featured
cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
sort = cur.fetchone()[0]
cur.execute(
    """
    INSERT INTO wallpapers (
        id, name, description, description_rich, type, category, tags,
        image_path, preview_path, image_size, preview_size,
        glow_color, badge, sort_order, featured, trending_score,
        published, daily_eligible, author_name, media_width, media_height
    ) VALUES (
        %s, %s, %s, %s, 'static'::wallpaper_type, 'WALLPAPERS'::wallpaper_category, %s,
        %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, false, 0,
        true, false, %s, %s, %s
    ) RETURNING id;
    """,
    (STATIC_ID, "Ariel · La Sirenita · Estatico", DESC_PLAIN, DESC_RICH, STATIC_TAGS,
     f"{STATIC_ID}.webp", f"{STATIC_ID}_preview.webp", len(flat_body), len(prev_body),
     GLOW, sort, "Pixora Studio", TARGET[0], TARGET[1]),
)
print(f"    static: {cur.fetchone()[0]}")

conn.commit()
cur.close()
conn.close()

print()
print("=" * 60)
print("DONE — Ariel · La Sirenita uploaded")
print(f"  scene id:  {SCENE_ID}  (3D LIVE, 2-frame swim sprite)")
print(f"  static id: {STATIC_ID} (WALLPAPERS)")
print(f"  sprite anchor x={norm_x} y={norm_y} scale={sprite_scale} skip={FRAME_SKIP}")
print("  -> Refresca el sprite editor: Ariel aparece con 2 objetos (fondo, ariel)")
print("  -> Ajusta la posicion de Ariel arrastrandola en el editor")
print("=" * 60)
