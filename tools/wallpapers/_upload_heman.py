"""Upload He-Man · Amos del Universo — canonical v2 formula.

Same pattern as Broly/Sailor Moon, no animated sprite (He-Man's power
sword lightning is already baked into the subject PNG).

  - fondo: cover-fit 1080x2340, parallax=0.0 (static)
  - heman (subject): bake_subject_complete v2, parallax=0.85

Assets in C:/Users/lalo/Desktop/wallPapers_repo/nuevos/heman/:
  - heman_solo_fondo_live.png       (1080x1920 background)
  - heman_solo_personage.png        (1080x1920 transparent subject)
  - heman__wallpaper_estatico.png   (composited flat)
"""
import json
import re
import shutil
import sys
import urllib.request
from pathlib import Path
from PIL import Image
import numpy as np

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
TARGET = (1080, 2340)
SCENE_ID = "heman_grayskull"
STATIC_ID = "heman_grayskull_static"
SUBJECT_KEY = "heman"

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/heman")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_heman")
if WORK.exists():
    shutil.rmtree(WORK)
WORK.mkdir(parents=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)


# ============================================================
# Storage helpers
# ============================================================
def put(bucket, remote, body, ct="image/webp"):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body, method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"    PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def put_json(bucket, remote, data):
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    put(bucket, remote, body, "application/json")


def get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


# ============================================================
# Image helpers (same formulas as _upload_ryu_reset.py)
# ============================================================
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


def bake_subject_complete(im, margin: float = 0.15):
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    a = np.array(im)[:, :, 3]
    ys, xs = np.where(a > 30)
    if len(xs) == 0:
        return im, 1.0
    sx0, sy0 = int(xs.min()), int(ys.min())
    sx1, sy1 = int(xs.max()) + 1, int(ys.max()) + 1
    subj_w, subj_h = sx1 - sx0, sy1 - sy0
    tight = im.crop((sx0, sy0, sx1, sy1))
    tw, th = TARGET
    max_w = tw * (1.0 - 2 * margin)
    max_h = th * (1.0 - 2 * margin)
    fit = min(max_w / subj_w, max_h / subj_h)
    new_w, new_h = int(round(subj_w * fit)), int(round(subj_h * fit))
    tight_resized = tight.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    canvas.alpha_composite(tight_resized, ((tw - new_w) // 2, (th - new_h) // 2))
    runtime_scale = round(tw / new_w, 4)
    return canvas, runtime_scale


def encode_webp(img, out_path, quality=90):
    img.save(out_path, "WEBP", quality=quality, method=6)
    return out_path.read_bytes()


# ============================================================
# Main
# ============================================================
print("=" * 60)
print("Upload He-Man · Amos del Universo — v2 canonical formula")
print("=" * 60)

# ---------------------------------
# Phase 1 — Bake assets
# ---------------------------------
print("\n[1/4] Baking assets (formula v2)...")

# Background: cover-fit RGB, scale 1.22 baked NO — scale lives in spec.
fondo_img = cover_fit_rgb(Image.open(SRC / "heman_solo_fondo_live.png"))
fondo_body = encode_webp(fondo_img, WORK / f"{SCENE_ID}_fondo.webp", quality=90)

# Subject: bake_subject_complete
subject_baked, runtime_scale = bake_subject_complete(
    Image.open(SRC / "heman_solo_personage.png"))
subject_body = encode_webp(subject_baked, WORK / f"{SCENE_ID}_{SUBJECT_KEY}.webp", quality=92)
print(f"    runtime_scale = {runtime_scale}")

# Flat + preview from composited estatico
flat_img = cover_fit_rgb(Image.open(SRC / "heman__wallpaper_estatico.png"))
flat_body = encode_webp(flat_img, WORK / f"{SCENE_ID}.webp", quality=88)
prev = flat_img.copy()
prev.thumbnail((540, 1170), Image.LANCZOS)
prev_body = encode_webp(prev, WORK / f"{SCENE_ID}_preview.webp", quality=85)

# ---------------------------------
# Phase 2 — Upload to Storage
# ---------------------------------
print("\n[2/4] Uploading to Supabase Storage...")
put(IMG_BUCKET, f"{SCENE_ID}_fondo.webp", fondo_body)
put(IMG_BUCKET, f"{SCENE_ID}_{SUBJECT_KEY}.webp", subject_body)
put(IMG_BUCKET, f"{SCENE_ID}.webp", flat_body)
put(IMG_BUCKET, f"{SCENE_ID}_preview.webp", prev_body)
put(IMG_BUCKET, f"{STATIC_ID}.webp", flat_body)
put(IMG_BUCKET, f"{STATIC_ID}_preview.webp", prev_body)

# ---------------------------------
# Phase 3 — Build spec + catalog_index
# ---------------------------------
print("\n[3/4] Building spec + updating catalog_index...")
url_bg = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}_fondo.webp"
url_subject = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}_{SUBJECT_KEY}.webp"
url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}.webp"
url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}_preview.webp"

TITLE = {"es": "He-Man · Amos del Universo", "en": "He-Man · Masters of the Universe"}
TAGS = ["heman", "masters_of_the_universe", "grayskull", "retro", "80s",
        "anime", "cartoon", "3d", "parallax"]

spec = {
    "schema_version": 1,
    "id": SCENE_ID,
    "type": "canvas_scene",
    "title": TITLE,
    "tags": TAGS,
    "category": "cartoon",
    "featured": True,
    "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
    "image_layers": [
        {
            "key": "fondo",
            "url": url_bg,
            "z": 0,
            "parallax_factor": 0.0,
            "scroll_factor": 0.0,
            "scale": 1.22,
            "offset_x_px": 0,
            "offset_y_px": 0,
            "revision": 1,
        },
        {
            "key": SUBJECT_KEY,
            "url": url_subject,
            "z": 1,
            "parallax_factor": 0.85,
            "scroll_factor": 0.0,
            "scale": runtime_scale,
            "offset_x_px": 0,
            "offset_y_px": 0,
            "revision": 1,
        },
    ],
    "sprites": [],
    "particles": [],
    "events": [],
}
put_json(SCENES_BUCKET, f"{SCENE_ID}.json", spec)

# catalog_index
try:
    cat = get_json(IMG_BUCKET, "catalog_index.json")
except Exception:
    cat = {"version": 0, "items": []}
cat["version"] = (cat.get("version", 0) or 0) + 1
entry = {
    "id": SCENE_ID,
    "type": "canvas_scene",
    "schema": 1,
    "title": TITLE,
    "preview_url": url_prev,
    "image_url": url_flat,
    "tags": TAGS,
    "category": "cartoon",
    "featured": True,
    "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{SCENE_ID}.json",
}
items = [it for it in cat.get("items", []) if it.get("id") != SCENE_ID]
items.insert(0, entry)
cat["items"] = items
put_json(IMG_BUCKET, "catalog_index.json", cat)

# ---------------------------------
# Phase 4 — Postgres
# ---------------------------------
print("\n[4/4] Registering in Postgres...")
conn = connect()
cur = conn.cursor()

cur.execute("DELETE FROM wallpapers WHERE id IN (%s, %s);", (SCENE_ID, STATIC_ID))
print(f"    deleted {cur.rowcount} old rows")

# Insert scene (canvas_scene → SCENES category)
cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
sort = cur.fetchone()[0]
cur.execute(
    """
    INSERT INTO wallpapers (
        id, name, description, type, category, tags,
        image_path, preview_path, image_size, preview_size,
        glow_color, badge, sort_order, featured, trending_score,
        published, daily_eligible, author_name, media_width, media_height
    ) VALUES (
        %s, %s, %s, 'static'::wallpaper_type, 'SCENES'::wallpaper_category, %s,
        %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, true, 0,
        true, false, %s, %s, %s
    )
    RETURNING id;
    """,
    (
        SCENE_ID, "He-Man · Amos del Universo",
        "He-Man con la Espada de Poder frente al Castillo de Grayskull — parallax 3D",
        TAGS, f"{SCENE_ID}.webp", f"{SCENE_ID}_preview.webp",
        len(flat_body), len(prev_body), "#FF4D2E", sort, "Pixora Studio",
        TARGET[0], TARGET[1],
    ),
)
print(f"    scene: {cur.fetchone()[0]}")

# Insert static → WALLPAPERS category, cleaned tags, not featured
STATIC_TAGS = ["heman", "masters_of_the_universe", "grayskull", "retro", "cartoon"]
cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
sort = cur.fetchone()[0]
cur.execute(
    """
    INSERT INTO wallpapers (
        id, name, description, type, category, tags,
        image_path, preview_path, image_size, preview_size,
        glow_color, badge, sort_order, featured, trending_score,
        published, daily_eligible, author_name, media_width, media_height
    ) VALUES (
        %s, %s, %s, 'static'::wallpaper_type, 'WALLPAPERS'::wallpaper_category, %s,
        %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, false, 0,
        true, false, %s, %s, %s
    )
    RETURNING id;
    """,
    (
        STATIC_ID, "He-Man · Amos del Universo · Estatico",
        "He-Man — imagen estatica sin parallax",
        STATIC_TAGS, f"{STATIC_ID}.webp", f"{STATIC_ID}_preview.webp",
        len(flat_body), len(prev_body), "#FF4D2E", sort, "Pixora Studio",
        TARGET[0], TARGET[1],
    ),
)
print(f"    static: {cur.fetchone()[0]}")

conn.commit()
cur.close()
conn.close()

print()
print("=" * 60)
print("DONE — He-Man · Amos del Universo uploaded (canonical v2)")
print(f"  scene id: {SCENE_ID}")
print(f"  static id: {STATIC_ID}")
print(f"  subject runtime_scale: {runtime_scale}")
print(f"  edit position in sprite editor, then apply on device")
print("=" * 60)
