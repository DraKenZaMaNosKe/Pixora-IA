"""Upload Guido Anchovy (Samurai Pizza Cats) — static + canvas_scene (3D LIVE)
with an animated ROTATING sunburst background.

Same animated-background pattern as samurai_pizza_cats, but the 4 background
frames carry a bright blue "guide line" that points UP / RIGHT / DOWN / LEFT.
Ordering them clockwise (up→right→down→left) makes the beam spin around, so
the sunburst reads as rotating behind Guido. The cat rides on top as a
parallax layer. User fine-tunes position + cycle order in the sprite editor.

Assets in C:/Users/lalo/Desktop/wallPapers_repo/nuevos/spcats/spc_azul/:
  - solofono_lineaguiaArriba.png / _derecha / _abajo / _izquierda  (bg frames)
  - solo_personage.png                (1080x1920 transparent blue Guido)
  - spcats_wallpaperestatico.png      (composited flat -> static + preview)
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

SCENE_ID = "guido_anchovy"
STATIC_ID = "guido_anchovy_static"

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/spcats/spc_azul")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_guido")

SK = re.findall(
    r"eyJ[A-Za-z0-9_\-\.]{100,500}",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
)[0]

TITLE = {"es": "Guido Anchovy", "en": "Guido Anchovy"}
TAGS = ["samurai_pizza_cats", "guido", "anchovy", "gato", "samurai", "anime",
        "retro", "90s", "sunburst", "3d", "parallax"]
STATIC_TAGS = ["samurai_pizza_cats", "guido", "anchovy", "gato", "samurai", "anime", "retro", "90s"]
GLOW = "#2E6FE8"

DESC_PLAIN = ("Guido Anchovy, el galan del trio de Samurai Pizza Cats, gira su "
              "inconfundible sombrilla sobre un estallido de rayos giratorio. Playboy "
              "y espadachin, la usa para volar y atacar. Del clasico Kyatto Ninden "
              "Teyandee de 1990, Guido es puro estilo y presumida elegancia felina.")
DESC_RICH = ("[[name:Guido Anchovy]], el galan del trio de [[name:Samurai Pizza Cats]], "
             "gira su inconfundible [[power:sombrilla]] sobre un estallido de rayos "
             "giratorio. Playboy y espadachin, la usa para [[power:volar y atacar]]. Del "
             "clasico [[name:Kyatto Ninden Teyandee]] de 1990, Guido es puro estilo y "
             "presumida [[emotion:elegancia felina]].")

# Clockwise rotation: up -> right -> down -> left (guide line spins around).
CYCLE_DURATION = 0.6
FONDO_FILES = ["solofono_lineaguiaArriba.png", "solofono_lineaguia_derecha.png",
               "solofono_lineaguia_abajo.png", "solofono_lineaguia_izquierda.png"]
FONDO_KEYS = ["fondo_00", "fondo_01", "fondo_02", "fondo_03"]


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
    fit = min(tw * (1.0 - 2 * margin) / subj_w, th * (1.0 - 2 * margin) / subj_h)
    new_w, new_h = int(round(subj_w * fit)), int(round(subj_h * fit))
    tight_resized = tight.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    canvas.alpha_composite(tight_resized, ((tw - new_w) // 2, (th - new_h) // 2))
    return canvas, round(tw / new_w, 4)


def encode_webp(img, out_path, quality=90):
    img.save(out_path, "WEBP", quality=quality, method=6)
    return out_path.read_bytes()


print("=" * 60)
print("Upload Guido Anchovy — rotating sunburst background")
print("=" * 60)

_kMarkup = re.compile(r"\[\[(\w+):(.*?)\]\]", re.DOTALL)
if _kMarkup.sub(lambda m: m.group(2), DESC_RICH) != DESC_PLAIN:
    raise SystemExit("MARKUP MISMATCH — abort")

if WORK.exists():
    shutil.rmtree(WORK)
WORK.mkdir(parents=True)

print(f"\n[1/5] Baking {len(FONDO_FILES)} bg frames + cat + flat...")
fondo_bodies = {}
for fname, key in zip(FONDO_FILES, FONDO_KEYS):
    img = cover_fit_rgb(Image.open(SRC / fname))
    fondo_bodies[key] = encode_webp(img, WORK / f"{SCENE_ID}_{key}.webp", quality=88)

cat_baked, cat_scale = bake_subject_complete(Image.open(SRC / "solo_personage.png"))
cat_body = encode_webp(cat_baked, WORK / f"{SCENE_ID}_guido.webp", quality=92)
print(f"    guido runtime_scale = {cat_scale}")

flat_img = cover_fit_rgb(Image.open(SRC / "spcats_wallpaperestatico.png"))
flat_body = encode_webp(flat_img, WORK / f"{SCENE_ID}.webp", quality=88)
prev = flat_img.copy()
prev.thumbnail((540, 1170), Image.LANCZOS)
prev_body = encode_webp(prev, WORK / f"{SCENE_ID}_preview.webp", quality=85)

print("\n[2/5] Uploading to Storage...")
for key, body in fondo_bodies.items():
    put(IMG_BUCKET, f"{SCENE_ID}_{key}.webp", body)
put(IMG_BUCKET, f"{SCENE_ID}_guido.webp", cat_body)
put(IMG_BUCKET, f"{SCENE_ID}.webp", flat_body)
put(IMG_BUCKET, f"{SCENE_ID}_preview.webp", prev_body)
put(IMG_BUCKET, f"{STATIC_ID}.webp", flat_body)
put(IMG_BUCKET, f"{STATIC_ID}_preview.webp", prev_body)

print("\n[3/5] Building spec (image_layers + rotating cycle)...")
def url(name):
    return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{name}"

url_flat = url(f"{SCENE_ID}.webp")
url_prev = url(f"{SCENE_ID}_preview.webp")

try:
    _existing = get_json(SCENES_BUCKET, f"{SCENE_ID}.json")
    REVISION = max((int(l.get("revision", 1)) for l in _existing.get("image_layers", [])), default=1) + 1
except Exception:
    REVISION = 1
print(f"    revision -> {REVISION}")

image_layers = []
for key in FONDO_KEYS:
    image_layers.append({
        "key": key, "url": url(f"{SCENE_ID}_{key}.webp"), "z": 0,
        "parallax_factor": 0.25, "scroll_factor": 0.0, "scale": 1.22,
        "offset_x_px": 0, "offset_y_px": 0, "revision": REVISION,
    })
image_layers.append({
    "key": "guido", "url": url(f"{SCENE_ID}_guido.webp"), "z": 1,
    "parallax_factor": 0.95, "scroll_factor": 0.0, "scale": cat_scale,
    "offset_x_px": 0, "offset_y_px": 0, "revision": REVISION,
})

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
    "schema_version": 1, "id": SCENE_ID, "type": "canvas_scene",
    "title": TITLE, "tags": TAGS, "category": "anime", "featured": True,
    "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
    "image_layers": image_layers, "cycles": [cycle],
    "sprites": [], "particles": [], "events": [],
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
    (SCENE_ID, "Guido Anchovy", DESC_PLAIN, DESC_RICH, TAGS,
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
    (STATIC_ID, "Guido Anchovy", DESC_PLAIN, DESC_RICH, STATIC_TAGS,
     f"{STATIC_ID}.webp", f"{STATIC_ID}_preview.webp", len(flat_body), len(prev_body),
     GLOW, sort, "Pixora Studio", TARGET[0], TARGET[1]),
)
print(f"    static: {cur.fetchone()[0]}")

conn.commit()
cur.close()
conn.close()

print()
print("=" * 60)
print("DONE — Guido Anchovy uploaded")
print(f"  scene id:  {SCENE_ID}  (3D LIVE, rotating sunburst)")
print(f"  cycle: sunburst_spin {CYCLE_DURATION}s · orden arriba->derecha->abajo->izquierda")
print(f"  guido runtime_scale={cat_scale}")
print("=" * 60)
