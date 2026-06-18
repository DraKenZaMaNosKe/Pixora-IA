"""
Pixora content publisher — Mario en su cuarto haciendo stream de NES.

Source: C:/Users/lalo/Desktop/wallPapers_repo/nuevos/mario/mario_en_stream.png
Output: 1 STATIC wallpaper, category GAMING, featured + boosted trending_score.

featured=true → entra al hero banner rotation
trending_score=100 → top del orden, recibe el slot duplicado del hero
                     (ver heroBannerProvider modificado para dar 2 slots al top)
"""
from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/mario/mario_en_stream.png")
WORK_DIR = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_mario")

OUT_WEBP = WORK_DIR / "mario_stream_nes.webp"
OUT_PREVIEW = WORK_DIR / "mario_stream_nes_preview.webp"

BUCKET = "wallpaper-images"
IMG_REMOTE = "mario_stream_nes.webp"
PREV_REMOTE = "mario_stream_nes_preview.webp"

WALL_ID = "mario_stream_nes"
TAGS = ["mario", "nintendo", "nes", "gaming", "retro", "stream",
        "pixel_art", "videojuegos", "cuarto", "nostalgia"]
GLOW = "#E63946"  # Mario red
HERO_BOOST_SCORE = 100  # mayor que el default 0 — gana el slot duplicado


def load_service_key() -> str:
    keys = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", keys)
    if not m:
        raise SystemExit("Service Role Key no encontrado")
    return m.group(1)


SERVICE_KEY = load_service_key()


def storage_put(bucket, remote, local, content_type):
    body = local.read_bytes()
    url = f"{PROJECT}/storage/v1/object/{bucket}/{remote}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", content_type)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote}  -> {r.status} ({len(body):,} bytes)")
    return len(body)


def phase1_process():
    from PIL import Image
    print("\n[1/4] Procesamiento local")
    WORK_DIR.mkdir(parents=True, exist_ok=True)

    img = Image.open(SRC).convert("RGB")  # PNG sin alpha real
    info = {"w": img.width, "h": img.height}
    img.save(OUT_WEBP, "WEBP", quality=90, method=6)
    info["webp_size"] = OUT_WEBP.stat().st_size
    print(f"  · main {img.width}x{img.height} -> {info['webp_size']:,} bytes")

    prev = img.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_PREVIEW, "WEBP", quality=85, method=6)
    info["prev_size"] = OUT_PREVIEW.stat().st_size
    print(f"  · preview {prev.width}x{prev.height} -> {info['prev_size']:,} bytes")
    return info


def phase2_upload():
    print("\n[2/4] Upload Storage")
    storage_put(BUCKET, IMG_REMOTE, OUT_WEBP, "image/webp")
    storage_put(BUCKET, PREV_REMOTE, OUT_PREVIEW, "image/webp")


def phase3_postgres(info):
    print("\n[3/4] INSERT Postgres wallpapers")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    print(f"  sort_order: {next_sort}, trending_score: {HERO_BOOST_SCORE}")
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'GAMING'::wallpaper_category, %s,
            %s, %s, %s, %s,
            %s, 'NEW'::wallpaper_badge, %s, true, %s,
            true, true, %s, %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            description = EXCLUDED.description,
            tags = EXCLUDED.tags,
            image_path = EXCLUDED.image_path,
            preview_path = EXCLUDED.preview_path,
            image_size = EXCLUDED.image_size,
            preview_size = EXCLUDED.preview_size,
            glow_color = EXCLUDED.glow_color,
            featured = EXCLUDED.featured,
            trending_score = EXCLUDED.trending_score,
            published = EXCLUDED.published,
            daily_eligible = EXCLUDED.daily_eligible,
            media_width = EXCLUDED.media_width,
            media_height = EXCLUDED.media_height,
            updated_at = now()
        RETURNING id;
    """, (
        WALL_ID,
        "Mario · Stream de NES",
        "Mario en su cuarto retro haciendo stream de juegos clasicos de NES — pixel art nostalgico con luces RGB",
        TAGS,
        IMG_REMOTE,
        PREV_REMOTE,
        info["webp_size"],
        info["prev_size"],
        GLOW,
        next_sort,
        HERO_BOOST_SCORE,
        "Pixora Studio",
        info["w"],
        info["h"],
    ))
    print(f"  upserted: {cur.fetchone()[0]}")
    conn.commit(); cur.close(); conn.close()


def phase4_fcm():
    print("\n[4/4] FCM invalidate")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")


if __name__ == "__main__":
    print("=" * 60)
    print("Mario Stream NES — static + hero-boost publisher")
    print("=" * 60)
    if not SRC.exists(): raise SystemExit(f"No existe {SRC}")
    info = phase1_process()
    phase2_upload()
    phase3_postgres(info)
    phase4_fcm()
    print("\n" + "=" * 60)
    print(f"Mario publicado · {info['w']}x{info['h']} · GAMING · featured · trending={HERO_BOOST_SCORE}")
    print("Cuando la app de hero-boost en heroBannerProvider esté live,")
    print("Mario aparecera 2 de cada 6 rotaciones (~33% del tiempo).")
