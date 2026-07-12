"""Upload Marvin el Marciano — static + canvas_scene (3D LIVE).

Scene composition:
  z=0  fondo (marvin_solofondo, no character / no rocket)  — far parallax
  z=1  Marvin blink cycle (3 frames, same position)        — near parallax
  sprite: cohete — TranslateController, crosses the scene diagonally
          (top-right -> bottom-left) and loops (respawn) every ~24s.

The 3 Marvin frames are pixel-aligned (x[203-850] y[380-1522]) and sit in
the SAME spot Marvin occupied in the original scene, so cover-fitting them
drops Marvin straight into place over the clean background. User fine-tunes
position + timings in the sprite editor afterwards.

Assets in C:/Users/lalo/Desktop/wallPapers_repo/nuevos/marvin/:
  - marvin_solofondo.png          (1080x1920 clean background)
  - marvin_ojos_abiertos.png      (1080x1920 transparent, Marvin only)
  - marvin_ojos_entreabiertos.png
  - marvin_ojos_cerrados.png
  - cohete.png                    (1080x1920 transparent, rocket top-right)
  - marvin_wallpaper_estatico.png (composited flat -> static + preview)
"""
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
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))   # tools/  -> apply_migration
sys.path.insert(0, str(Path(__file__).resolve().parent))          # tools/wallpapers/ -> sprite utils
from apply_migration import connect
from sprite_pack_utils import upload_sprite_pack

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
TARGET = (1080, 2340)

SCENE_ID = "marvin_marciano"
STATIC_ID = "marvin_marciano_static"
ROCKET_KEY = "marvin_cohete"

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/marvin")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_marvin")

SK = re.findall(
    r"eyJ[A-Za-z0-9_\-\.]{100,500}",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
)[0]

TITLE = {"es": "Marvin el Marciano", "en": "Marvin the Martian"}
TAGS = ["marvin", "marciano", "looney_tunes", "warner", "espacio", "luna",
        "cohete", "retro", "caricatura", "3d", "parallax"]
STATIC_TAGS = ["marvin", "marciano", "looney_tunes", "warner", "espacio",
               "luna", "retro", "caricatura"]
GLOW = "#6DB33F"

DESC_PLAIN = ("Marvin el Marciano, el villano mas educado del cosmos, vigila la "
              "Tierra desde su planeta rojo. Creado por Chuck Jones en 1948 para "
              "los Looney Tunes, sueña con destruirla porque le tapa la vista de "
              "Venus. Con su casco romano y su Modulador Explosivo Illudium PU-36, "
              "es puro estilo galactico y frustracion comica.")
DESC_RICH = ("[[name:Marvin el Marciano]], el villano mas educado del cosmos, vigila "
             "la Tierra desde su planeta rojo. Creado por [[name:Chuck Jones]] en 1948 "
             "para los [[name:Looney Tunes]], sueña con destruirla porque le tapa la "
             "vista de [[name:Venus]]. Con su casco romano y su [[power:Modulador "
             "Explosivo Illudium PU-36]], es puro estilo galactico y "
             "[[emotion:frustracion comica]].")

# Blink cycle: eyes open most of the time, quick blink every ~5s.
BLINK_DURATION = 5.4
BG_KEY = "fondo"
# Keys end in _open/_half/_shut so the sprite editor recognises them as ONE
# cycle group (cycleGroupPrefix regex) and moves/scales them together.
MARVIN_KEYS = ["marvin_open", "marvin_half", "marvin_shut"]
MARVIN_FILES = ["marvin_ojos_abiertos.png", "marvin_ojos_entreabiertos.png",
                "marvin_ojos_cerrados.png"]


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


def cover_fit_rgba(img, target=TARGET):
    """Same cover-fit as the background but PRESERVES alpha (for Marvin)."""
    tw, th = target
    src = img.convert("RGBA")
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(round(sw * scale)), int(round(sh * scale))
    resized = src.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    return resized.crop((left, top, left + tw, top + th))


def crop_tight(img):
    """Crop to the non-transparent bounding box (for the rocket sprite)."""
    im = img.convert("RGBA")
    a = np.array(im)[:, :, 3]
    ys, xs = np.where(a > 30)
    x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
    return im.crop((x0, y0, x1, y1))


def encode_webp(img, out_path, quality=90):
    img.save(out_path, "WEBP", quality=quality, method=6)
    return out_path.read_bytes()


print("=" * 60)
print("Upload Marvin el Marciano — blink cycle + crossing rocket")
print("=" * 60)

_kMarkup = re.compile(r"\[\[(\w+):(.*?)\]\]", re.DOTALL)
if _kMarkup.sub(lambda m: m.group(2), DESC_RICH) != DESC_PLAIN:
    raise SystemExit("MARKUP MISMATCH — abort")

if WORK.exists():
    shutil.rmtree(WORK)
WORK.mkdir(parents=True)

print("\n[1/6] Baking background + 3 Marvin frames + flat...")
bg_img = cover_fit_rgb(Image.open(SRC / "marvin_solofondo.png"))
bg_body = encode_webp(bg_img, WORK / f"{SCENE_ID}_{BG_KEY}.webp", quality=88)

marvin_bodies = {}
for key, fname in zip(MARVIN_KEYS, MARVIN_FILES):
    m = cover_fit_rgba(Image.open(SRC / fname))
    marvin_bodies[key] = encode_webp(m, WORK / f"{SCENE_ID}_{key}.webp", quality=92)

flat_img = cover_fit_rgb(Image.open(SRC / "marvin_wallpaper_estatico.png"))
flat_body = encode_webp(flat_img, WORK / f"{SCENE_ID}.webp", quality=88)
prev = flat_img.copy()
prev.thumbnail((540, 1170), Image.LANCZOS)
prev_body = encode_webp(prev, WORK / f"{SCENE_ID}_preview.webp", quality=85)

print("\n[2/6] Packing rocket sprite (1 frame) + uploading pack...")
rocket_tight = crop_tight(Image.open(SRC / "cohete.png"))
(WORK / "frame_001.png").write_bytes(b"")  # placeholder to ensure parent exists
rocket_tight.save(WORK / "frame_001.png", "PNG")
zip_path = WORK / f"{ROCKET_KEY}.zip"
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    zf.write(WORK / "frame_001.png", "frame_001.png")
pack = upload_sprite_pack(ROCKET_KEY, zip_path, service_key=SK)
print(f"    sprite pack: {pack}")

print("\n[3/6] Uploading images to Storage...")
put(IMG_BUCKET, f"{SCENE_ID}_{BG_KEY}.webp", bg_body)
for key, body in marvin_bodies.items():
    put(IMG_BUCKET, f"{SCENE_ID}_{key}.webp", body)
put(IMG_BUCKET, f"{SCENE_ID}.webp", flat_body)
put(IMG_BUCKET, f"{SCENE_ID}_preview.webp", prev_body)
put(IMG_BUCKET, f"{STATIC_ID}.webp", flat_body)
put(IMG_BUCKET, f"{STATIC_ID}_preview.webp", prev_body)


def url(name):
    return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{name}"


url_flat = url(f"{SCENE_ID}.webp")
url_prev = url(f"{SCENE_ID}_preview.webp")

print("\n[4/6] Building spec (layers + blink cycle + rocket translate)...")
try:
    _existing = get_json(SCENES_BUCKET, f"{SCENE_ID}.json")
    REVISION = max((int(l.get("revision", 1)) for l in _existing.get("image_layers", [])), default=1) + 1
except Exception:
    REVISION = 1
print(f"    revision -> {REVISION}")

image_layers = [{
    "key": BG_KEY, "url": url(f"{SCENE_ID}_{BG_KEY}.webp"), "z": 0,
    "parallax_factor": 0.12, "scroll_factor": 0.0, "scale": 1.12,
    "offset_x_px": 0, "offset_y_px": 0, "revision": REVISION,
}]
for i, key in enumerate(MARVIN_KEYS):
    image_layers.append({
        "key": key, "url": url(f"{SCENE_ID}_{key}.webp"), "z": 1,
        "parallax_factor": 0.42, "scroll_factor": 0.0, "scale": 1.12,
        "offset_x_px": 0, "offset_y_px": 0, "revision": REVISION,
        "initial_alpha": 1.0 if i == 0 else 0.0,
    })

# Blink: open dominates, quick half->closed->half->open near the end.
blink = {
    "name": "blink",
    "duration_s": BLINK_DURATION,
    "frames": [
        {"layer_key": "marvin_open", "from_s": 0.0, "to_s": 4.80},
        {"layer_key": "marvin_half", "from_s": 4.80, "to_s": 4.95},
        {"layer_key": "marvin_shut", "from_s": 4.95, "to_s": 5.15},
        {"layer_key": "marvin_half", "from_s": 5.15, "to_s": 5.30},
        {"layer_key": "marvin_open", "from_s": 5.30, "to_s": BLINK_DURATION},
    ],
}

# Rocket crosses top-right -> bottom-left and loops. from/to extend well off
# screen so it's visible ~9s of every ~24s (reads as "every once in a while").
rocket_sprite = {
    "name": "cohete",
    "manifest_key": ROCKET_KEY,
    "behavior": "translate",
    "default_facing": "left",   # art already points down-left; don't flip
    "frame_skip": 2,
    "params": {
        "from": [2.0, -0.6],
        "to": [-0.8, 1.3],
        "duration_s": 24.0,
        "scale": 0.0011,
        "alpha": 255,
    },
}

spec = {
    "schema_version": 1, "id": SCENE_ID, "type": "canvas_scene",
    "title": TITLE, "tags": TAGS, "category": "cartoon", "featured": True,
    "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
    "image_layers": image_layers, "cycles": [blink],
    "sprites": [rocket_sprite], "particles": [], "events": [],
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
    "category": "cartoon", "featured": True, "glow_color": GLOW,
    "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{SCENE_ID}.json",
}
items = [it for it in cat.get("items", []) if it.get("id") != SCENE_ID]
items.insert(0, entry)
cat["items"] = items
put_json(IMG_BUCKET, "catalog_index.json", cat)

print("\n[5/6] Registering scene in Postgres...")
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
    (SCENE_ID, "Marvin el Marciano", DESC_PLAIN, DESC_RICH, TAGS,
     f"{SCENE_ID}.webp", f"{SCENE_ID}_preview.webp", len(flat_body), len(prev_body),
     GLOW, sort, "Pixora Studio", TARGET[0], TARGET[1]),
)
print(f"    scene: {cur.fetchone()[0]}")

print("[6/6] Registering static in Postgres...")
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
    (STATIC_ID, "Marvin el Marciano", DESC_PLAIN, DESC_RICH, STATIC_TAGS,
     f"{STATIC_ID}.webp", f"{STATIC_ID}_preview.webp", len(flat_body), len(prev_body),
     GLOW, sort, "Pixora Studio", TARGET[0], TARGET[1]),
)
print(f"    static: {cur.fetchone()[0]}")

conn.commit()
cur.close()
conn.close()

print()
print("=" * 60)
print("DONE — Marvin el Marciano uploaded")
print(f"  scene id:  {SCENE_ID}  (3D LIVE)")
print(f"  blink cycle: {BLINK_DURATION}s (open -> half -> closed -> half -> open)")
print(f"  rocket: translate [2.0,-0.6] -> [-0.8,1.3], loop 24s")
print("  Ajusta posiciones/timings en el sprite editor.")
print("=" * 60)
