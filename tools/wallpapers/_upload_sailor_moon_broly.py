"""Upload Sailor Moon + Broly (canvas_scene + static, 2 each = 4 total).

Follows the subject-complete formula v2 (2026-06-30):
  - fondo: cover-fit to TARGET (1080x2340), parallax bajo (0.35)
  - subject: bake_subject_complete (15% margin + runtime scale),
             parallax alto (0.85)

No sprite animation — Eduardo tweaks scale/offset in the sprite
editor after upload if needed (same flow as Ryu/Superman).
"""
import io
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

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_sailormoon_broly")
if WORK.exists():
    shutil.rmtree(WORK)
WORK.mkdir(parents=True)

# ============================================================
# Wallpapers config
# ============================================================
WALLPAPERS = [
    {
        "id": "sailor_moon",
        "src_dir": Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/sailor_moon"),
        "fondo_file": "sailor_moon_soloFondo.png",
        "subject_file": "sailor_moon_solo_personage.png",
        "flat_file": "sailor_moon_wallpaper_estatico.png",
        "name_scene": "Sailor Moon",
        "name_static": "Sailor Moon · Estatico",
        "description": "Sailor Moon, la guerrera de la luna, sobre pedestal magico bajo luna llena. Auras vaporwave cyan y rosa envuelven la escena — magical girl con vibra retro-cosmica.",
        "glow": "#EC4899",
        "tags": ["sailor_moon", "anime", "magical_girl", "luna", "vaporwave", "kawaii", "retro", "cosmico"],
    },
    {
        "id": "broly",
        "src_dir": Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/broly"),
        "fondo_file": "broly_solofondo.png",
        "subject_file": "broly_solobroly.png",
        "flat_file": "broly_wallpaper_estatico.png",
        "name_scene": "Broly Legendary",
        "name_static": "Broly Legendary · Estatico",
        "description": "Broly Legendary Super Saiyan sobre rocas flotantes con energia verde explosiva y portal de ki emergiendo del crater. Escenario apocaliptico epico de Dragon Ball.",
        "glow": "#22C55E",
        "tags": ["broly", "dragon_ball", "super_saiyan", "anime", "videojuegos", "ki", "epico", "goku"],
    },
]


# ============================================================
# Helpers
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


def cover_fit_rgb(img, target=TARGET):
    """Cover-fit to target keeping RGB (for opaque backgrounds/composites)."""
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
    """Formula v2: subject stays inside TARGET with margin.
    Returns (canvas_rgba, runtime_scale)."""
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
    return out_path.read_bytes(), img


# ============================================================
# Main
# ============================================================
print("=" * 60)
print(f"Upload Sailor Moon + Broly · 4 wallpapers (2 canvas_scene + 2 static)")
print("=" * 60)

conn = connect()
cur = conn.cursor()

for w in WALLPAPERS:
    src = w["src_dir"]
    wid = w["id"]
    print(f"\n\n{'=' * 60}\n[{wid.upper()}]\n{'=' * 60}")

    # -------------------------------------------------
    # 1. STATIC wallpaper
    # -------------------------------------------------
    print(f"\n--- {wid}_static ---")
    static_id = f"{wid}_static"
    flat_src = src / w["flat_file"]
    if not flat_src.exists():
        raise SystemExit(f"MISSING: {flat_src}")
    flat_img = cover_fit_rgb(Image.open(flat_src))
    flat_webp = WORK / f"{static_id}.webp"
    flat_body, _ = encode_webp(flat_img, flat_webp, quality=90)
    # preview
    prev = flat_img.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev_webp = WORK / f"{static_id}_preview.webp"
    prev_body, _ = encode_webp(prev, prev_webp, quality=82)
    put(IMG_BUCKET, f"{static_id}.webp", flat_body)
    put(IMG_BUCKET, f"{static_id}_preview.webp", prev_body)

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
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description, tags=EXCLUDED.tags,
            image_path=EXCLUDED.image_path, preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color, featured=EXCLUDED.featured,
            published=EXCLUDED.published, media_width=EXCLUDED.media_width,
            media_height=EXCLUDED.media_height, updated_at=now()
        RETURNING id;
        """,
        (
            static_id, w["name_static"], w["description"], w["tags"],
            f"{static_id}.webp", f"{static_id}_preview.webp",
            len(flat_body), len(prev_body), w["glow"], sort, "Pixora Studio",
            TARGET[0], TARGET[1],
        ),
    )
    print(f"    postgres static: {cur.fetchone()[0]}")

    # -------------------------------------------------
    # 2. CANVAS_SCENE (fondo + subject with parallax)
    # -------------------------------------------------
    print(f"\n--- {wid} (canvas_scene) ---")
    fondo_src = src / w["fondo_file"]
    subject_src = src / w["subject_file"]
    if not fondo_src.exists():
        raise SystemExit(f"MISSING: {fondo_src}")
    if not subject_src.exists():
        raise SystemExit(f"MISSING: {subject_src}")

    # Fondo — cover-fit RGB (opaque)
    fondo_img = cover_fit_rgb(Image.open(fondo_src))
    fondo_webp = WORK / f"{wid}_fondo.webp"
    fondo_body, _ = encode_webp(fondo_img, fondo_webp, quality=90)

    # Subject — bake with formula v2
    subject_baked, runtime_scale = bake_subject_complete(Image.open(subject_src))
    subject_webp = WORK / f"{wid}_{wid}.webp"  # e.g. sailor_moon_sailor_moon.webp
    subject_body, _ = encode_webp(subject_baked, subject_webp, quality=92)
    print(f"    subject runtime_scale = {runtime_scale}")

    # Flat + preview (reuse the static ones)
    scene_flat_webp = WORK / f"{wid}.webp"
    scene_flat_body, _ = encode_webp(flat_img, scene_flat_webp, quality=88)
    scene_prev_webp = WORK / f"{wid}_preview.webp"
    scene_prev_body, _ = encode_webp(prev, scene_prev_webp, quality=85)

    put(IMG_BUCKET, f"{wid}_fondo.webp", fondo_body)
    put(IMG_BUCKET, f"{wid}_{wid}.webp", subject_body)
    put(IMG_BUCKET, f"{wid}.webp", scene_flat_body)
    put(IMG_BUCKET, f"{wid}_preview.webp", scene_prev_body)

    # Scene spec
    url_bg = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{wid}_fondo.webp"
    url_subject = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{wid}_{wid}.webp"
    url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{wid}.webp"
    url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{wid}_preview.webp"

    spec = {
        "schema_version": 1,
        "id": wid,
        "type": "canvas_scene",
        "title": {"es": w["name_scene"], "en": w["name_scene"]},
        "tags": w["tags"],
        "category": "scenes",
        "featured": True,
        "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
        "image_layers": [
            {
                # 2026-07-04 — fondo estático (parallax=0). Eduardo prefiere
                # que solo el subject se mueva; el fondo fijo evita la
                # sensación de "brinco" en devices donde el gyro tiene drift.
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
                "key": wid,
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
        "sprites": [],
        "particles": [],
        "events": [],
    }
    put_json(SCENES_BUCKET, f"{wid}.json", spec)

    # catalog_index update
    try:
        cat = get_json(IMG_BUCKET, "catalog_index.json")
    except Exception:
        cat = {"version": 0, "items": []}
    cat["version"] = (cat.get("version", 0) or 0) + 1
    entry = {
        "id": wid,
        "type": "canvas_scene",
        "schema": 1,
        "title": spec["title"],
        "preview_url": url_prev,
        "image_url": url_flat,
        "tags": w["tags"],
        "category": "scenes",
        "featured": True,
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{wid}.json",
    }
    items = cat.get("items", [])
    items = [it for it in items if it.get("id") != wid]
    items.insert(0, entry)
    cat["items"] = items
    put_json(IMG_BUCKET, "catalog_index.json", cat)
    print(f"    catalog_index v{cat['version']} · {len(items)} items")

    # Postgres (same pattern as Ryu: registered as 'static' type but SCENES category
    # to appear in the SCENES grid; app resolves canvas_scene via catalog_index)
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
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description, tags=EXCLUDED.tags,
            image_path=EXCLUDED.image_path, preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color, featured=EXCLUDED.featured,
            published=EXCLUDED.published, media_width=EXCLUDED.media_width,
            media_height=EXCLUDED.media_height, updated_at=now()
        RETURNING id;
        """,
        (
            wid, w["name_scene"], w["description"], w["tags"],
            f"{wid}.webp", f"{wid}_preview.webp",
            len(scene_flat_body), len(scene_prev_body), w["glow"], sort, "Pixora Studio",
            TARGET[0], TARGET[1],
        ),
    )
    print(f"    postgres scene: {cur.fetchone()[0]}")

conn.commit()
cur.close()
conn.close()

# FCM invalidate
print(f"\n\n{'=' * 60}\nFCM invalidate\n{'=' * 60}")
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _fcm_push import send_catalog_invalidate
print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")
print(f"  live       -> {send_catalog_invalidate('live')}")

print(f"\n[OK] 4 wallpapers publicados (2 canvas_scene + 2 static)")
print(f"     Edit en sprite editor: http://127.0.0.1:5758/sprite-editor.html")
