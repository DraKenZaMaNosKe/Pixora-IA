"""Reset Ryu Hadouken from scratch — same canonical pattern as Broly/Sailor Moon.

Deletes the old ryu_hadouken.json + ryu_hadouken_static + all layer bitmaps
and re-uploads with:
  - fondo: cover-fit 1080x2340, parallax=0.0 (static)
  - ryu (subject): bake_subject_complete v2, parallax=0.85
  - orb: sprite ZIP from the GIF, positioned between his hands

Assets in C:/Users/lalo/Desktop/wallPapers_repo/nuevos/ryu/:
  - ryu_solo_fondo.png    (1080x1920 background)
  - ryu_solo_completo.png (1080x1920 transparent subject, uncropped)
  - ryu_wallpaper_estatico.png (composited flat)
  - ryu_/ryu_.gif         (orb animation frames)
"""
import io
import json
import re
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path
from PIL import Image
import numpy as np

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
SPRITES_BUCKET = "wallpaper-sprites"
TARGET = (1080, 2340)
SCENE_ID = "ryu_hadouken"
STATIC_ID = "ryu_hadouken_static"
ORB_MANIFEST_KEY = "ryu_hadouken_orb"
EXTRACT_FRAMES = 12

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/ryu")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_ryu_reset")
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


def delete(bucket, remote):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        method="DELETE",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            print(f"    DEL {bucket}/{remote} -> {r.status}")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"    DEL {bucket}/{remote} -> not found (ok)")
        else:
            print(f"    DEL {bucket}/{remote} -> {e.code} {e.reason}")


def put_json(bucket, remote, data):
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    put(bucket, remote, body, "application/json")


def get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


# ============================================================
# Image helpers (same formulas as _upload_sailor_moon_broly.py)
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
# Extract orb sprite from GIF
# ============================================================
def extract_orb_zip(gif_path):
    gif = Image.open(gif_path)
    total = 0
    while True:
        try:
            gif.seek(total)
            total += 1
        except EOFError:
            break
    indices = [int(i * total / EXTRACT_FRAMES) for i in range(EXTRACT_FRAMES)]

    # Find shared bbox across frames
    boxes = []
    for src_i in indices:
        gif.seek(src_i)
        frame = gif.convert("RGBA")
        bbox = frame.split()[3].getbbox()
        if bbox:
            boxes.append(bbox)
    x0 = max(0, min(b[0] for b in boxes) - 24)
    y0 = max(0, min(b[1] for b in boxes) - 24)
    x1 = min(gif.width, max(b[2] for b in boxes) + 24)
    y1 = min(gif.height, max(b[3] for b in boxes) + 24)
    print(f"    orb crop {x1-x0}x{y1-y0} from ({x0},{y0})")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for out_i, src_i in enumerate(indices, start=1):
            gif.seek(src_i)
            frame = gif.convert("RGBA").crop((x0, y0, x1, y1))
            fbuf = io.BytesIO()
            frame.save(fbuf, "PNG", optimize=True)
            zf.writestr(f"frame_{out_i:03d}.png", fbuf.getvalue())
    return buf.getvalue(), len(indices)


# ============================================================
# Main
# ============================================================
print("=" * 60)
print("Reset Ryu Hadouken — v2 canonical formula")
print("=" * 60)

# ---------------------------------
# Phase 1 — Delete old
# ---------------------------------
print("\n[1/6] Deleting old ryu_hadouken files from Storage...")
for f in [f"{SCENE_ID}_bg.webp", f"{SCENE_ID}_ryu.webp", f"{SCENE_ID}.webp",
          f"{SCENE_ID}_preview.webp", f"{SCENE_ID}_fondo.webp",
          f"{STATIC_ID}.webp", f"{STATIC_ID}_preview.webp"]:
    delete(IMG_BUCKET, f)
delete(SCENES_BUCKET, f"{SCENE_ID}.json")

# ---------------------------------
# Phase 2 — Bake assets
# ---------------------------------
print("\n[2/6] Baking assets (formula v2)...")

# Background: cover-fit RGB
fondo_img = cover_fit_rgb(Image.open(SRC / "ryu_solo_fondo.png"))
fondo_body = encode_webp(fondo_img, WORK / f"{SCENE_ID}_fondo.webp", quality=90)

# Subject: bake_subject_complete (using UNCROPPED source per user preference)
subject_baked, runtime_scale = bake_subject_complete(Image.open(SRC / "ryu_solo_completo.png"))
subject_body = encode_webp(subject_baked, WORK / f"{SCENE_ID}_ryu.webp", quality=92)
print(f"    runtime_scale = {runtime_scale}")

# Flat + preview from composited estatico
flat_img = cover_fit_rgb(Image.open(SRC / "ryu_wallpaper_estatico.png"))
flat_body = encode_webp(flat_img, WORK / f"{SCENE_ID}.webp", quality=88)
prev = flat_img.copy()
prev.thumbnail((540, 1170), Image.LANCZOS)
prev_body = encode_webp(prev, WORK / f"{SCENE_ID}_preview.webp", quality=85)

# ---------------------------------
# Phase 3 — Orb sprite ZIP
# ---------------------------------
print("\n[3/6] Extracting orb sprite ZIP...")
orb_zip_body, orb_frames = extract_orb_zip(SRC / "ryu_" / "ryu_.gif")
print(f"    orb: {orb_frames} frames, {len(orb_zip_body):,} bytes")

# ---------------------------------
# Phase 4 — Upload everything
# ---------------------------------
print("\n[4/6] Uploading to Supabase Storage...")
put(IMG_BUCKET, f"{SCENE_ID}_fondo.webp", fondo_body)
put(IMG_BUCKET, f"{SCENE_ID}_ryu.webp", subject_body)
put(IMG_BUCKET, f"{SCENE_ID}.webp", flat_body)
put(IMG_BUCKET, f"{SCENE_ID}_preview.webp", prev_body)
put(SPRITES_BUCKET, f"{ORB_MANIFEST_KEY}.zip", orb_zip_body, "application/zip")

# Static wallpaper
put(IMG_BUCKET, f"{STATIC_ID}.webp", flat_body)
put(IMG_BUCKET, f"{STATIC_ID}_preview.webp", prev_body)

# Update sprite manifest with new orb
try:
    manifest = get_json(SPRITES_BUCKET, "manifest.json")
except Exception:
    manifest = {}
manifest[ORB_MANIFEST_KEY] = {
    "zip": f"{ORB_MANIFEST_KEY}.zip",
    "frames": orb_frames,
    "size": len(orb_zip_body),
}
put_json(SPRITES_BUCKET, "manifest.json", manifest)

# ---------------------------------
# Phase 5 — Build spec + upload
# ---------------------------------
print("\n[5/6] Building spec + updating catalog_index...")
url_bg = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}_fondo.webp"
url_subject = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}_ryu.webp"
url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}.webp"
url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{SCENE_ID}_preview.webp"

TAGS = ["ryu", "street fighter", "hadouken", "fighting", "anime", "capcom",
        "3d", "parallax", "live", "animated", "energy"]

spec = {
    "schema_version": 1,
    "id": SCENE_ID,
    "type": "canvas_scene",
    "title": {"es": "Ryu Cargando Poder", "en": "Ryu Hadouken"},
    "tags": TAGS,
    "category": "scenes",
    "featured": True,
    "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
    "image_layers": [
        {
            "key": "fondo",
            "url": url_bg,
            "z": 0,
            "parallax_factor": 0.0,
            "scroll_factor": 0.0,
            "scale": 1.0,
            "offset_x_px": 0,
            "offset_y_px": 0,
            "revision": 1,
        },
        {
            "key": "ryu",
            "url": url_subject,
            "z": 1,
            "parallax_factor": 0.85,
            "scroll_factor": 0.85,
            "scale": runtime_scale,
            "offset_x_px": 0,
            "offset_y_px": 0,
            "revision": 1,
        },
    ],
    "sprites": [
        {
            "name": "orb",
            "manifest_key": ORB_MANIFEST_KEY,
            "behavior": "static",
            "frame_skip": 2.8,
            "params": {
                "x": 0.5,
                "y": 0.55,
                "scale": 0.0010,
                "alpha": 255,
                "parallax_factor": 0.85,
                "high_res": True,
            },
        },
    ],
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
    "title": spec["title"],
    "preview_url": url_prev,
    "image_url": url_flat,
    "tags": TAGS,
    "category": "scenes",
    "featured": True,
    "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{SCENE_ID}.json",
}
items = [it for it in cat.get("items", []) if it.get("id") != SCENE_ID]
items.insert(0, entry)
cat["items"] = items
put_json(IMG_BUCKET, "catalog_index.json", cat)

# ---------------------------------
# Phase 6 — Postgres
# ---------------------------------
print("\n[6/6] Registering in Postgres...")
conn = connect()
cur = conn.cursor()

# Delete old Ryu rows (canvas_scene + static)
cur.execute("DELETE FROM wallpapers WHERE id IN (%s, %s);", (SCENE_ID, STATIC_ID))
print(f"    deleted {cur.rowcount} old rows")

# Insert scene
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
        SCENE_ID, "Ryu Cargando Poder",
        "Ryu de Street Fighter cargando su Hadouken — parallax 3D y esfera de energia animada",
        TAGS, f"{SCENE_ID}.webp", f"{SCENE_ID}_preview.webp",
        len(flat_body), len(prev_body), "#00B4FF", sort, "Pixora Studio",
        TARGET[0], TARGET[1],
    ),
)
print(f"    scene: {cur.fetchone()[0]}")

# Insert static
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
        STATIC_ID, "Ryu Cargando Poder · Estatico",
        "Ryu con Hadouken — imagen estatica sin parallax",
        TAGS, f"{STATIC_ID}.webp", f"{STATIC_ID}_preview.webp",
        len(flat_body), len(prev_body), "#00B4FF", sort, "Pixora Studio",
        TARGET[0], TARGET[1],
    ),
)
print(f"    static: {cur.fetchone()[0]}")

conn.commit()
cur.close()
conn.close()

print()
print("=" * 60)
print("DONE — Ryu Hadouken reset with canonical v2 formula")
print(f"  scene id: {SCENE_ID}")
print(f"  static id: {STATIC_ID}")
print(f"  subject runtime_scale: {runtime_scale}")
print(f"  ready to test — apply the wallpaper on your device")
print("=" * 60)
