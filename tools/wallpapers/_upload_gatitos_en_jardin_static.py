"""Static wallpaper: Gatitos en el Jardín."""
import re
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC = Path(
    r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/gatitos_en_jardin"
    r"/gatitos_en_el_jardin_wallpaper_estatico.png"
)
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_gatitos_en_jardin")
OUT_WEBP = WORK / "gatitos_en_jardin.webp"
OUT_PREV = WORK / "gatitos_en_jardin_preview.webp"

BUCKET = "wallpaper-images"
IMG_REMOTE = "gatitos_en_jardin.webp"
PREV_REMOTE = "gatitos_en_jardin_preview.webp"
WALL_ID = "gatitos_en_jardin"
TAGS = ["cats", "kittens", "garden", "cute", "animals", "fence", "kawaii",
        "summer", "nature", "gatitos"]
GLOW = "#84CC16"
TARGET_W, TARGET_H = 1080, 2340


def load_service_key():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_service_key()


def put(bucket, remote, local, ct):
    body = local.read_bytes()
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body, method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=60) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def main():
    from PIL import Image

    if not SRC.exists():
        raise SystemExit(f"No existe {SRC}")

    WORK.mkdir(parents=True, exist_ok=True)
    print("[1/3] WebP")
    img = Image.open(SRC).convert("RGB")
    if img.size != (TARGET_W, TARGET_H):
        img = img.resize((TARGET_W, TARGET_H), Image.LANCZOS)
        print(f"  resized {SRC.name} -> {TARGET_W}x{TARGET_H}")
    info = {"w": img.width, "h": img.height}
    img.save(OUT_WEBP, "WEBP", quality=90, method=6)
    info["webp"] = OUT_WEBP.stat().st_size
    print(f"  main {img.width}x{img.height} -> {info['webp']:,} B")
    prev = img.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_PREV, "WEBP", quality=85, method=6)
    info["prev"] = OUT_PREV.stat().st_size
    print(f"  preview {prev.width}x{prev.height} -> {info['prev']:,} B")

    print("\n[2/3] Storage")
    put(BUCKET, IMG_REMOTE, OUT_WEBP, "image/webp")
    put(BUCKET, PREV_REMOTE, OUT_PREV, "image/webp")

    print("\n[3/3] INSERT Postgres + FCM")
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
            %s, %s, %s, 'static'::wallpaper_type, 'ANIMALS'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, true, 0,
            true, true, %s, %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description, tags=EXCLUDED.tags,
            image_path=EXCLUDED.image_path, preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color, badge=EXCLUDED.badge,
            featured=EXCLUDED.featured, published=EXCLUDED.published,
            daily_eligible=EXCLUDED.daily_eligible,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            updated_at=now()
        RETURNING id;
        """,
        (
            WALL_ID,
            "Gatitos en el Jardín",
            "Dos gatitos kawaii asomándose por una valla de madera en un jardín soleado — blanco y negro con ojos brillantes",
            TAGS,
            IMG_REMOTE,
            PREV_REMOTE,
            info["webp"],
            info["prev"],
            GLOW,
            next_sort,
            "Pixora Studio",
            info["w"],
            info["h"],
        ),
    )
    print(f"  upserted: {cur.fetchone()[0]}")
    conn.commit()
    cur.close()
    conn.close()

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate

    print(f"  FCM wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print(f"\nGatitos static publicado · {info['w']}x{info['h']} · ANIMALS")


if __name__ == "__main__":
    main()