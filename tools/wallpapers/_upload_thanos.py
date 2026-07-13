"""Upload Thanos — static + canvas_scene (3D LIVE).

Scene composition:
  z=0  fondo (solofondo, cosmic nebula + asteroids)   — far parallax
  z=1  Thanos gauntlet cycle (3 frames, same position) — near parallax

The animation is a continuous "open/close" of the Infinity Gauntlet (and,
subtly, the eyes) — fist closed -> half -> open (gems glowing) -> half ->
closed, looping every ~6s. No sprites.

The 3 Thanos frames come from Grok's imagine-edit (720x1280, 9:16), body
pixel-locked (bbox x[85..637] y[140..1237] across all 3), only the hand and
eyes change. They are pre-scaled to 1080x1920 (same 9:16 canvas as the
background) so cover-fitting scales BOTH by the same factor and Thanos lands
in the same spot he occupies in the flat static — no cross-aspect drift.

Assets in C:/Users/lalo/Desktop/wallPapers_repo/nuevos/thanos_new/:
  - solofondo.png            (1080x1920 clean cosmic background)
  - thanos_frame_01.png      (720x1280 transparent — eyes open, fist closed)
  - thanos_frame_02.png      (720x1280 transparent — half)
  - thanos_frame_03.png      (720x1280 transparent — eyes closed, fist open, gems glowing)
  - wallpaper_estatico.png   (1080x1920 composited flat -> static + preview)
"""
import json
import re
import shutil
import sys
import urllib.request
from pathlib import Path

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))   # tools/ -> apply_migration
sys.path.insert(0, str(Path(__file__).resolve().parent))          # tools/wallpapers/

from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
TARGET = (1080, 2340)

SCENE_ID = "thanos_infinito"
STATIC_ID = "thanos_infinito_static"

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/thanos_new")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_thanos")

SK = re.findall(
    r"eyJ[A-Za-z0-9_\-\.]{100,500}",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
)[0]

TITLE = {"es": "Thanos", "en": "Thanos"}
TAGS = ["thanos", "marvel", "avengers", "guantelete", "infinito", "gemas",
        "cosmos", "villano", "titan", "3d", "parallax"]
STATIC_TAGS = ["thanos", "marvel", "avengers", "guantelete", "infinito",
               "gemas", "cosmos", "villano", "titan"]
GLOW = "#8A4FFF"

DESC_PLAIN = ("Thanos, el Titán Loco, empuña el Guantelete del Infinito con las seis "
              "Gemas del Infinito. Con un solo chasquido borró la mitad del universo "
              "buscando su retorcida idea de equilibrio. Creado por Jim Starlin en "
              "1973, es el villano más imponente del cosmos Marvel.")
DESC_RICH = ("[[name:Thanos]], el Titán Loco, empuña el [[power:Guantelete del "
             "Infinito]] con las seis [[power:Gemas del Infinito]]. Con un solo "
             "chasquido borró la mitad del universo buscando su retorcida idea de "
             "[[emotion:equilibrio]]. Creado por [[name:Jim Starlin]] en 1973, es el "
             "villano más imponente del cosmos [[name:Marvel]].")

BG_KEY = "fondo"
# Generic cycle keys (avoid _open/_half/_shut so the editor treats them as ONE
# explicit cycle group, not the blink auto-grouper).
THANOS_KEYS = ["thanos_01", "thanos_02", "thanos_03"]
THANOS_FILES = ["thanos_frame_01.png", "thanos_frame_02.png", "thanos_frame_03.png"]
GAUNTLET_DURATION = 6.0


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
    """Cover-fit preserving alpha (for the Thanos frames)."""
    tw, th = target
    src = img.convert("RGBA")
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(round(sw * scale)), int(round(sh * scale))
    resized = src.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    return resized.crop((left, top, left + tw, top + th))


def encode_webp(img, out_path, quality=90):
    img.save(out_path, "WEBP", quality=quality, method=6)
    return out_path.read_bytes()


print("=" * 60)
print("Upload Thanos — gauntlet open/close cycle (3D LIVE)")
print("=" * 60)

_kMarkup = re.compile(r"\[\[(\w+):(.*?)\]\]", re.DOTALL)
if _kMarkup.sub(lambda m: m.group(2), DESC_RICH) != DESC_PLAIN:
    raise SystemExit("MARKUP MISMATCH — abort")

if WORK.exists():
    shutil.rmtree(WORK)
WORK.mkdir(parents=True)

print("\n[1/5] Baking background + 3 Thanos frames + flat...")
bg_img = cover_fit_rgb(Image.open(SRC / "solofondo.png"))
bg_body = encode_webp(bg_img, WORK / f"{SCENE_ID}_{BG_KEY}.webp", quality=88)

thanos_bodies = {}
for key, fname in zip(THANOS_KEYS, THANOS_FILES):
    # Pre-scale 720x1280 -> 1080x1920 (same 9:16 canvas as the bg) so cover-fit
    # scales this frame by the SAME factor as the background = aligned.
    raw = Image.open(SRC / fname).convert("RGBA").resize((1080, 1920), Image.LANCZOS)
    m = cover_fit_rgba(raw)
    thanos_bodies[key] = encode_webp(m, WORK / f"{SCENE_ID}_{key}.webp", quality=92)

flat_img = cover_fit_rgb(Image.open(SRC / "wallpaper_estatico.png"))
flat_body = encode_webp(flat_img, WORK / f"{SCENE_ID}.webp", quality=88)
prev = flat_img.copy()
prev.thumbnail((540, 1170), Image.LANCZOS)
prev_body = encode_webp(prev, WORK / f"{SCENE_ID}_preview.webp", quality=85)


def url(name):
    return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{name}"


print("\n[2/5] Uploading images to Storage...")
put(IMG_BUCKET, f"{SCENE_ID}_{BG_KEY}.webp", bg_body)
for key, body in thanos_bodies.items():
    put(IMG_BUCKET, f"{SCENE_ID}_{key}.webp", body)
put(IMG_BUCKET, f"{SCENE_ID}.webp", flat_body)
put(IMG_BUCKET, f"{SCENE_ID}_preview.webp", prev_body)
put(IMG_BUCKET, f"{STATIC_ID}.webp", flat_body)
put(IMG_BUCKET, f"{STATIC_ID}_preview.webp", prev_body)

url_flat = url(f"{SCENE_ID}.webp")
url_prev = url(f"{SCENE_ID}_preview.webp")

print("\n[3/5] Building spec (layers + gauntlet cycle)...")
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
for i, key in enumerate(THANOS_KEYS):
    image_layers.append({
        "key": key, "url": url(f"{SCENE_ID}_{key}.webp"), "z": 1,
        "parallax_factor": 0.42, "scroll_factor": 0.0, "scale": 1.12,
        "offset_x_px": 0, "offset_y_px": 0, "revision": REVISION,
        "initial_alpha": 1.0 if i == 0 else 0.0,
    })

# Gauntlet open/close: closed (hold) -> half -> open+gems (hold) -> half -> closed.
gauntlet = {
    "name": "gauntlet",
    "duration_s": GAUNTLET_DURATION,
    "frames": [
        {"layer_key": "thanos_01", "from_s": 0.00, "to_s": 1.60},
        {"layer_key": "thanos_02", "from_s": 1.60, "to_s": 2.30},
        {"layer_key": "thanos_03", "from_s": 2.30, "to_s": 4.00},
        {"layer_key": "thanos_02", "from_s": 4.00, "to_s": 4.70},
        {"layer_key": "thanos_01", "from_s": 4.70, "to_s": GAUNTLET_DURATION},
    ],
}

spec = {
    "schema_version": 1, "id": SCENE_ID, "type": "canvas_scene",
    "title": TITLE, "tags": TAGS, "category": "movies", "featured": True,
    "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
    "image_layers": image_layers, "cycles": [gauntlet],
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
    "category": "movies", "featured": True, "glow_color": GLOW,
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
    (SCENE_ID, "Thanos", DESC_PLAIN, DESC_RICH, TAGS,
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
    (STATIC_ID, "Thanos", DESC_PLAIN, DESC_RICH, STATIC_TAGS,
     f"{STATIC_ID}.webp", f"{STATIC_ID}_preview.webp", len(flat_body), len(prev_body),
     GLOW, sort, "Pixora Studio", TARGET[0], TARGET[1]),
)
print(f"    static: {cur.fetchone()[0]}")

conn.commit()
cur.close()
conn.close()

print()
print("=" * 60)
print("DONE — Thanos uploaded")
print(f"  scene id:  {SCENE_ID}  (3D LIVE)")
print(f"  gauntlet cycle: {GAUNTLET_DURATION}s (closed -> half -> open+gems -> half -> closed)")
print(f"  static id: {STATIC_ID}  (WALLPAPERS)")
print("  Ajusta posición/timings en el sprite editor si hace falta.")
print("=" * 60)
