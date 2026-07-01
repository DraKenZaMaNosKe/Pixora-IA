"""Upload Superman + Luisa canvas_scene to Pixora.

Follows the subject-complete formula (v2, 2026-06-30):
  - fondo (llamas): cover-fit to TARGET (1080x2340), parallax bajo (0.35)
  - superman: bake_subject_complete (15% margin + runtime scale),
              parallax alto (0.85)

Sin sprite animation ni cycles — Eduardo ajusta scale y offset en el
sprite editor despues del upload, mismo flujo que Ryu.

Asset structure (source: C:/Users/lalo/Desktop/wallPapers_repo/nuevos/superman/):
- superman_solofondo.png            -> background (1080x1920, llamas)
- superman_solo_personage.png       -> Superman cargando a Luisa, alpha bg
- superman_wallapper_estatico.png   -> composite plano (typo original mantenido),
                                        se usa como flat + preview
"""
import io
import json
import re
import shutil
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/superman")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_superman_luisa")

SRC_BG = SRC / "superman_solofondo.png"
SRC_HERO = SRC / "superman_solo_personage.png"
SRC_FLAT = SRC / "superman_wallapper_estatico.png"

TARGET = (1080, 2340)
SCENE_ID = "superman_luisa"

IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"

R_BG = f"{SCENE_ID}_fondo.webp"
R_HERO = f"{SCENE_ID}_superman.webp"
R_FLAT = f"{SCENE_ID}.webp"
R_PREVIEW = f"{SCENE_ID}_preview.webp"
R_SPEC = f"{SCENE_ID}.json"
R_CATALOG = "catalog_index.json"

TAGS = [
    "superman", "luisa", "lois", "dc", "hero", "heroe",
    "fire", "flames", "llamas", "epic", "dark", "snyder",
    "cinematic", "rescue", "cape", "parallax", "live", "3d",
]
GLOW = "#F97316"  # naranja incandescente


def load_service_key() -> str:
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_service_key()


def put(bucket: str, remote: str, local: Path, ct: str) -> int:
    body = local.read_bytes()
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body, method="PUT",
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
        data=payload, method="PUT",
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


def bake_subject_complete(im, margin: float = 0.15):
    """v2 formula: subject stays inside TARGET with margin, returns (canvas, runtime_scale)."""
    from PIL import Image
    import numpy as np
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


def phase1_process() -> dict:
    from PIL import Image
    print("\n[1/5] Local processing")
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True, exist_ok=True)

    for f in (SRC_BG, SRC_HERO, SRC_FLAT):
        if not f.exists():
            raise SystemExit(f"Missing source: {f}")

    # Fondo: cover-fit to TARGET (never pad with black bands)
    bg = cover_fit(Image.open(SRC_BG))
    out_bg = WORK / R_BG
    bg.save(out_bg, "WEBP", quality=90, method=6)
    print(f"  fondo cover-fit -> {out_bg.name} ({out_bg.stat().st_size:,} B)")

    # Superman: subject-complete bake
    hero_baked, hero_runtime_scale = bake_subject_complete(Image.open(SRC_HERO))
    out_hero = WORK / R_HERO
    hero_baked.save(out_hero, "WEBP", quality=92, method=6)
    print(f"  superman baked -> {out_hero.name} ({out_hero.stat().st_size:,} B) scale={hero_runtime_scale}")

    # Flat + preview from the composed static
    flat = cover_fit(Image.open(SRC_FLAT))
    out_flat = WORK / R_FLAT
    flat.save(out_flat, "WEBP", quality=88, method=6)
    prev = flat.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    out_prev = WORK / R_PREVIEW
    prev.save(out_prev, "WEBP", quality=85, method=6)
    print(f"  flat/preview -> {out_flat.name}/{out_prev.name}")

    return {
        "bg_w": TARGET[0],
        "bg_h": TARGET[1],
        "bg_size": out_bg.stat().st_size,
        "hero_size": out_hero.stat().st_size,
        "flat_size": out_flat.stat().st_size,
        "prev_size": out_prev.stat().st_size,
        "hero_runtime_scale": hero_runtime_scale,
    }


def phase2_upload(info: dict) -> None:
    print("\n[2/5] Upload assets")
    put(IMG_BUCKET, R_BG, WORK / R_BG, "image/webp")
    put(IMG_BUCKET, R_HERO, WORK / R_HERO, "image/webp")
    put(IMG_BUCKET, R_FLAT, WORK / R_FLAT, "image/webp")
    put(IMG_BUCKET, R_PREVIEW, WORK / R_PREVIEW, "image/webp")


def phase3_spec(info: dict) -> dict:
    print("\n[3/5] Scene spec")
    url_bg = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_BG}"
    url_hero = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_HERO}"
    url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_FLAT}"
    url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}"

    spec = {
        "schema_version": 1,
        "id": SCENE_ID,
        "type": "canvas_scene",
        "title": {"es": "Superman Cargando a Luisa", "en": "Superman Carrying Lois"},
        "tags": TAGS,
        "category": "scenes",
        "featured": True,
        "background": {
            "url": url_flat,
            "preview_url": url_prev,
            "scroll": False,
        },
        "image_layers": [
            {
                "key": "fondo",
                "url": url_bg,
                "z": 0,
                "parallax_factor": 0.35,
                "scroll_factor": 0.35,
                "scale": 1.0,
                "offset_x_px": 0,
                "offset_y_px": 0,
                "revision": 1,
            },
            {
                "key": "superman",
                "url": url_hero,
                "z": 1,
                "parallax_factor": 0.85,
                "scroll_factor": 0.85,
                "scale": info["hero_runtime_scale"],
                "offset_x_px": 0,
                "offset_y_px": 0,
                "revision": 1,
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
        "image_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_FLAT}",
        "tags": TAGS,
        "category": "scenes",
        "featured": True,
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{R_SPEC}",
    }
    items = cat.get("items", [])
    items = [it for it in items if it.get("id") != SCENE_ID]
    items.insert(0, entry)
    cat["items"] = items
    put_json(IMG_BUCKET, R_CATALOG, cat)
    print(f"  catalog_index v{cat['version']} ({len(items)} items)")

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
            "Superman Cargando a Luisa",
            "Superman en modo Snyder cut cargando a Luisa entre llamas — parallax cinematografico y fuego incandescente",
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
    print(f"  postgres upserted: {cur.fetchone()[0]}")
    conn.commit()
    cur.close()
    conn.close()


def phase5_fcm() -> None:
    print("\n[5/5] FCM invalidate")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print(f"  live       -> {send_catalog_invalidate('live')}")


if __name__ == "__main__":
    print("=" * 60)
    print("Superman + Luisa canvas_scene")
    print("=" * 60)
    info = phase1_process()
    phase2_upload(info)
    spec = phase3_spec(info)
    phase4_catalog_and_postgres(info, spec)
    phase5_fcm()
    print()
    print("DONE — Superman + Luisa canvas_scene shipped")
    print(f"  scene id: {SCENE_ID}")
    print(f"  edit in sprite editor: http://127.0.0.1:5758/sprite-editor.html")
    print()
