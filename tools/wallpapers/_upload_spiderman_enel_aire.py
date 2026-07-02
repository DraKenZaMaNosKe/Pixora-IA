"""
Spiderman en el Aire — canvas_scene 2-layer parallax (sin rebuild).

Layers:
  fondo_spiderman.png              → bg (parallax bajo)
  spiderman_soloelpersonage.png    → hero (parallax alto + bob sutil)
  spiderman_para_wallpaper_estatico.png → flat para grid WALL + preview
"""
from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/spiderman_enel_aire")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_spiderman_enel_aire")

SRC_BG = SRC / "fondo_spiderman.png"
SRC_HERO = SRC / "spiderman_soloelpersonage.png"
SRC_FLAT = SRC / "spiderman_para_wallpaper_estatico.png"

TARGET = (1080, 2340)

SCENE_ID = "spiderman_enel_aire"
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"

R_BG = f"{SCENE_ID}_bg.webp"
R_HERO = f"{SCENE_ID}_hero.webp"
R_FLAT = f"{SCENE_ID}.webp"
R_PREVIEW = f"{SCENE_ID}_preview.webp"
R_SPEC = f"{SCENE_ID}.json"
R_CATALOG = "catalog_index.json"

TAGS = [
    "spiderman", "marvel", "superhero", "cosmos", "space",
    "anime", "3d", "parallax", "live", "animated", "live3d",
]
GLOW = "#E62429"


def load_service_key() -> str:
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_service_key()


def put(bucket: str, remote: str, local: Path, ct: str) -> int:
    body = local.read_bytes()
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body,
        method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")
    return len(body)


def put_json(bucket: str, remote: str, data: dict) -> None:
    payload = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=payload,
        method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} (JSON)")


def get_json(bucket: str, remote: str) -> dict:
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def cover_fit(img, target=TARGET, transparent=False):
    """Scale-to-cover + center-crop — fills 1080x2340 with no letterbox bars."""
    from PIL import Image

    tw, th = target
    src = img.convert("RGBA")
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(round(sw * scale)), int(round(sh * scale))
    resized = src.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    cropped = resized.crop((left, top, left + tw, top + th))
    if not transparent:
        out = Image.new("RGB", target, (0, 0, 0))
        out.paste(cropped, mask=cropped.split()[3])
        return out
    return cropped


def phase1_process() -> dict:
    from PIL import Image

    print("\n[1/5] Procesamiento local")
    WORK.mkdir(parents=True, exist_ok=True)
    info: dict = {}

    bg_src = Image.open(SRC_BG)
    hero_src = Image.open(SRC_HERO)
    flat_src = Image.open(SRC_FLAT)

    bg = cover_fit(bg_src)
    hero = cover_fit(hero_src, transparent=True)
    flat = cover_fit(flat_src)

    out_bg = WORK / R_BG
    out_hero = WORK / R_HERO
    out_flat = WORK / R_FLAT
    out_prev = WORK / R_PREVIEW

    rgb_bg = Image.new("RGB", bg.size, (0, 0, 0))
    rgb_bg.paste(bg, mask=bg.split()[3])
    rgb_bg.save(out_bg, "WEBP", quality=90, method=6)

    hero.save(out_hero, "WEBP", quality=92, method=6)

    rgb_flat = Image.new("RGB", flat.size, (0, 0, 0))
    rgb_flat.paste(flat, mask=flat.split()[3])
    rgb_flat.save(out_flat, "WEBP", quality=88, method=6)

    prev = rgb_flat.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(out_prev, "WEBP", quality=85, method=6)

    info.update(
        {
            "bg_w": TARGET[0],
            "bg_h": TARGET[1],
            "bg_size": out_bg.stat().st_size,
            "hero_size": out_hero.stat().st_size,
            "flat_size": out_flat.stat().st_size,
            "prev_size": out_prev.stat().st_size,
        }
    )
    print(f"  · bg/hero/flat -> {TARGET[0]}x{TARGET[1]}")
    return info


def phase2_upload() -> None:
    print("\n[2/5] Upload assets")
    put(IMG_BUCKET, R_BG, WORK / R_BG, "image/webp")
    put(IMG_BUCKET, R_HERO, WORK / R_HERO, "image/webp")
    put(IMG_BUCKET, R_FLAT, WORK / R_FLAT, "image/webp")
    put(IMG_BUCKET, R_PREVIEW, WORK / R_PREVIEW, "image/webp")


def phase3_spec() -> dict:
    print("\n[3/5] Scene spec")
    url_bg = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_BG}"
    url_hero = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_HERO}"
    url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_FLAT}"
    url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}"

    spec = {
        "schema_version": 1,
        "id": SCENE_ID,
        "type": "canvas_scene",
        "title": {
            "en": "Spiderman in the Air",
            "es": "Spiderman en el Aire",
        },
        "tags": TAGS,
        "category": "anime",
        "featured": True,
        "background": {
            "url": url_flat,
            "preview_url": url_prev,
            "scroll": False,
        },
        "image_layers": [
            {
                "key": "cosmos",
                "url": url_bg,
                "z": 0,
                "parallax_factor": 0.35,
                "scroll_factor": 0.35,
                "scale": 1.0,
            },
            {
                "key": "spiderman",
                "url": url_hero,
                "z": 1,
                "parallax_factor": 0.82,
                "scroll_factor": 0.82,
                "scale": 1.0,
                "bob_amplitude_px": 28,
                "bob_period_sec": 5.8,
            },
        ],
        "sprites": [],
        "particles": [],
        "events": [],
    }
    put_json(SCENES_BUCKET, R_SPEC, spec)
    return spec


def phase4_catalog_and_postgres(info: dict, spec: dict) -> None:
    print("\n[4/5] catalog_index + Postgres")
    cat = get_json(IMG_BUCKET, R_CATALOG)
    cat["version"] = (cat.get("version", 0) or 0) + 1
    entry = {
        "id": SCENE_ID,
        "type": "canvas_scene",
        "schema": 1,
        "title": spec["title"],
        "preview_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}",
        "tags": TAGS,
        "category": "anime",
        "featured": True,
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{R_SPEC}",
    }
    items = cat.get("items", [])
    items = [it for it in items if it.get("id") != SCENE_ID]
    items.insert(0, entry)
    cat["items"] = items
    put_json(IMG_BUCKET, R_CATALOG, cat)
    print(f"  · catalog_index v{cat['version']} ({len(items)} items)")

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
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
            glow_color=EXCLUDED.glow_color, badge=EXCLUDED.badge,
            featured=EXCLUDED.featured, published=EXCLUDED.published,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            updated_at=now()
        RETURNING id;
        """,
        (
            SCENE_ID,
            "Spiderman en el Aire",
            "Spiderman colgando en el cosmos — parallax 3D al inclinar el celular con flotación sutil",
            TAGS,
            R_FLAT,
            R_PREVIEW,
            info["flat_size"],
            info["prev_size"],
            GLOW,
            next_sort,
            "Pixora Studio",
            info["bg_w"],
            info["bg_h"],
        ),
    )
    print(f"  · postgres upserted: {cur.fetchone()[0]}")
    conn.commit()
    cur.close()
    conn.close()


def phase5_fcm() -> None:
    print("\n[5/5] FCM invalidate")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate

    print(f"  · wallpapers -> {send_catalog_invalidate('wallpapers')}")


if __name__ == "__main__":
    print("=" * 60)
    print("Spiderman en el Aire — canvas_scene parallax publisher")
    print("=" * 60)
    for src in (SRC_BG, SRC_HERO, SRC_FLAT):
        if not src.exists():
            raise SystemExit(f"No existe {src}")
    info = phase1_process()
    phase2_upload()
    spec = phase3_spec()
    phase4_catalog_and_postgres(info, spec)
    phase5_fcm()
    print("\n" + "=" * 60)
    print("Spiderman en el Aire publicado (sin rebuild)")
    print(f"  · spec: wallpaper-scenes/{R_SPEC}")
    print(f"  · parallax: cosmos=0.35, spiderman=0.82 + bob 28px/5.8s")
    print("=" * 60)