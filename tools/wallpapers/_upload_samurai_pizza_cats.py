"""Upload Samurai Pizza Cats — static + canvas_scene (3D LIVE) with an
ANIMATED BACKGROUND (a first for the catalog).

Unlike Ariel (animated character over a static bg), here the BACKGROUND is
what animates: three sunburst frames (fondo_animado_00/01/02) are time-
multiplexed by a `cycle` so the rays spin/pulse like a classic 90s anime
power-up backdrop. The samurai cat rides on top as a parallax layer.

Assets in C:/Users/lalo/Desktop/wallPapers_repo/nuevos/spcats/001/:
  - fondo_animado_00.png / _01.png / _02.png  (1080x1920 opaque sunburst frames)
  - solopersonage.png                         (1080x1920 transparent samurai cat)
  - wallpaper_estatico_samuray_pizza_cats.png (composited flat -> static + preview)

The cycle multiplexes fondo_00/01/02: at each moment exactly one is alpha=1,
the others alpha=0. Layers must share position/scale so it reads as animation
in place, not a jump. The user fine-tunes cat position + cycle speed after.
"""
import json
import re
import shutil
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
TARGET = (1080, 2340)

SCENE_ID = "samurai_pizza_cats"
STATIC_ID = "samurai_pizza_cats_static"

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/spcats")        # 4 fondos
SRC_SUBJ = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/spcats/001")  # personaje + estatico
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_spcats")

SK = re.findall(
    r"eyJ[A-Za-z0-9_\-\.]{100,500}",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
)[0]

TITLE = {"es": "Samurai Pizza Cats", "en": "Samurai Pizza Cats"}
TAGS = ["samurai_pizza_cats", "gato", "samurai", "anime", "retro", "90s",
        "sunburst", "3d", "parallax"]
STATIC_TAGS = ["samurai_pizza_cats", "gato", "samurai", "anime", "retro", "90s"]
GLOW = "#F5B301"

DESC_PLAIN = ("Los Samurai Pizza Cats (Kyattō Ninden Teyandee, 1990) son gatos samurái "
              "robot que protegen la Pequeña Tokio desde su pizzería secreta. Producido "
              "por Tatsunoko, este clásico noventero se volvió de culto por su doblaje "
              "disparatado que inventaba chistes y rompía la cuarta pared. Aquí el felino "
              "desenfunda sus dos katanas sobre el mítico estallido de rayos, con toda la "
              "energía del anime de acción.")
DESC_RICH = ("Los [[name:Samurai Pizza Cats]] ([[name:Kyattō Ninden Teyandee]], 1990) son "
             "gatos samurái robot que protegen la [[place:Pequeña Tokio]] desde su pizzería "
             "secreta. Producido por [[name:Tatsunoko]], este clásico noventero se volvió de "
             "culto por su doblaje disparatado que inventaba chistes y rompía la cuarta "
             "pared. Aquí el felino desenfunda sus [[power:dos katanas]] sobre el mítico "
             "estallido de rayos, con toda la [[emotion:energía]] del anime de acción.")

# Sunburst cycle timing — 4 frames (360° spin), ~0.15s each = smooth rotation.
CYCLE_DURATION = 0.6
FONDO_FILES = ["fondo_animado_00.png", "fondo_animado_01.png",
               "fondo_animado_02.png", "fondo_animado_03.png"]
FONDO_KEYS = ["fondo_00", "fondo_01", "fondo_02", "fondo_03"]


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


def bake_subject_complete(im, margin: float = 0.13):
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
    return canvas, round(tw / new_w, 4)


def encode_webp(img, out_path, quality=90):
    img.save(out_path, "WEBP", quality=quality, method=6)
    return out_path.read_bytes()


# ============================================================
print("=" * 60)
print("Upload Samurai Pizza Cats — animated sunburst background")
print("=" * 60)

# Markup byte-identity guard
_kMarkup = re.compile(r"\[\[(\w+):(.*?)\]\]", re.DOTALL)
if _kMarkup.sub(lambda m: m.group(2), DESC_RICH) != DESC_PLAIN:
    raise SystemExit("MARKUP MISMATCH — abort")

if WORK.exists():
    shutil.rmtree(WORK)
WORK.mkdir(parents=True)

print(f"\n[1/5] Baking {len(FONDO_FILES)} sunburst frames + cat + flat...")
fondo_bodies = {}
for fname, key in zip(FONDO_FILES, FONDO_KEYS):
    img = cover_fit_rgb(Image.open(SRC / fname))
    fondo_bodies[key] = encode_webp(img, WORK / f"{SCENE_ID}_{key}.webp", quality=88)

cat_baked, cat_scale = bake_subject_complete(Image.open(SRC_SUBJ / "solopersonage.png"))
cat_body = encode_webp(cat_baked, WORK / f"{SCENE_ID}_gato.webp", quality=92)
print(f"    cat runtime_scale = {cat_scale}")

flat_img = cover_fit_rgb(Image.open(SRC_SUBJ / "wallpaper_estatico_samuray_pizza_cats.png"))
flat_body = encode_webp(flat_img, WORK / f"{SCENE_ID}.webp", quality=88)
prev = flat_img.copy()
prev.thumbnail((540, 1170), Image.LANCZOS)
prev_body = encode_webp(prev, WORK / f"{SCENE_ID}_preview.webp", quality=85)

print("\n[2/5] Uploading to Storage...")
for key, body in fondo_bodies.items():
    put(IMG_BUCKET, f"{SCENE_ID}_{key}.webp", body)
put(IMG_BUCKET, f"{SCENE_ID}_gato.webp", cat_body)
put(IMG_BUCKET, f"{SCENE_ID}.webp", flat_body)
put(IMG_BUCKET, f"{SCENE_ID}_preview.webp", prev_body)
put(IMG_BUCKET, f"{STATIC_ID}.webp", flat_body)
put(IMG_BUCKET, f"{STATIC_ID}_preview.webp", prev_body)

print("\n[3/5] Building spec (image_layers + sunburst cycle)...")
def url(name):
    return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{name}"

url_flat = url(f"{SCENE_ID}.webp")
url_prev = url(f"{SCENE_ID}_preview.webp")

# 3 fondo layers (z=0, low parallax) + cat layer (z=1, high parallax).
image_layers = []
for key in FONDO_KEYS:
    image_layers.append({
        "key": key, "url": url(f"{SCENE_ID}_{key}.webp"), "z": 0,
        "parallax_factor": 0.25, "scroll_factor": 0.0, "scale": 1.22,
        "offset_x_px": 0, "offset_y_px": 0, "revision": 1,
    })
image_layers.append({
    "key": "gato", "url": url(f"{SCENE_ID}_gato.webp"), "z": 1,
    "parallax_factor": 0.95, "scroll_factor": 0.0, "scale": cat_scale,
    "offset_x_px": 0, "offset_y_px": 0, "revision": 1,
})

# Cycle multiplexes the N sunburst frames evenly (fondo_00 -> fondo_03 -> loop).
step = CYCLE_DURATION / len(FONDO_KEYS)
cycle = {
    "name": "sunburst_spin",
    "duration_s": CYCLE_DURATION,
    "frames": [
        {"layer_key": k, "from_s": round(i * step, 4), "to_s": round((i + 1) * step, 4)}
        for i, k in enumerate(FONDO_KEYS)
    ],
}

spec = {
    "schema_version": 1,
    "id": SCENE_ID,
    "type": "canvas_scene",
    "title": TITLE,
    "tags": TAGS,
    "category": "anime",
    "featured": True,
    "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
    "image_layers": image_layers,
    "cycles": [cycle],
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
    "id": SCENE_ID, "type": "canvas_scene", "schema": 1, "title": TITLE,
    "preview_url": url_prev, "image_url": url_flat, "tags": TAGS,
    "category": "anime", "featured": True, "glow_color": GLOW,
    "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{SCENE_ID}.json",
}
items = [it for it in cat.get("items", []) if it.get("id") != SCENE_ID]
items.insert(0, entry)
cat["items"] = items
put_json(IMG_BUCKET, "catalog_index.json", cat)

print("\n[4/5] Registering scene in Postgres...")
conn = connect()
cur = conn.cursor()
cur.execute("DELETE FROM wallpapers WHERE id IN (%s, %s);", (SCENE_ID, STATIC_ID))
print(f"    deleted {cur.rowcount} old rows")

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
    (SCENE_ID, "Samurai Pizza Cats", DESC_PLAIN, DESC_RICH, TAGS,
     f"{SCENE_ID}.webp", f"{SCENE_ID}_preview.webp", len(flat_body), len(prev_body),
     GLOW, sort, "Pixora Studio", TARGET[0], TARGET[1]),
)
print(f"    scene: {cur.fetchone()[0]}")

print("[5/5] Registering static in Postgres...")
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
    (STATIC_ID, "Samurai Pizza Cats", DESC_PLAIN, DESC_RICH, STATIC_TAGS,
     f"{STATIC_ID}.webp", f"{STATIC_ID}_preview.webp", len(flat_body), len(prev_body),
     GLOW, sort, "Pixora Studio", TARGET[0], TARGET[1]),
)
print(f"    static: {cur.fetchone()[0]}")

conn.commit()
cur.close()
conn.close()

print()
print("=" * 60)
print("DONE — Samurai Pizza Cats uploaded")
print(f"  scene id:  {SCENE_ID}  (3D LIVE, animated sunburst bg)")
print(f"  static id: {STATIC_ID} (WALLPAPERS)")
print(f"  cycle: sunburst_spin {CYCLE_DURATION}s over {len(FONDO_KEYS)} frames")
print(f"  cat runtime_scale={cat_scale} parallax=0.95")
print("  -> Sprite editor: ajusta posicion/tamano del gato y velocidad del cycle")
print("=" * 60)
