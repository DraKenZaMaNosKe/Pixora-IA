"""
Publisher rapido: solo el wallpaper estatico de Pokemon tomando cafe.
El 3D canvas_scene se sube por separado con _upload_pokemon_cafe_3d.py.
"""
import json, re, sys, urllib.request
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/pokemon/pokemon_tomando_cafesito_wallpaperestatico.png")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_pokemon")
OUT_WEBP = WORK / "pokemon_cafe.webp"
OUT_PREV = WORK / "pokemon_cafe_preview.webp"

BUCKET = "wallpaper-images"
IMG_REMOTE = "pokemon_cafe.webp"
PREV_REMOTE = "pokemon_cafe_preview.webp"
WALL_ID = "pokemon_cafe"
TAGS = ["pokemon", "pikachu", "cafe", "chimenea", "casa", "cozy",
        "anime", "videojuegos", "nintendo", "lluvia"]
GLOW = "#FFCB05"  # Pikachu yellow

def load_service_key():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)
SK = load_service_key()

def put(bucket, remote, local, ct):
    body = local.read_bytes()
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}", data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=60) as r: print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")

def main():
    from PIL import Image
    if not SRC.exists(): raise SystemExit(f"No existe {SRC}")
    WORK.mkdir(parents=True, exist_ok=True)
    print("[1/3] WebP")
    img = Image.open(SRC).convert("RGB")
    info = {"w": img.width, "h": img.height}
    img.save(OUT_WEBP, "WEBP", quality=90, method=6); info["webp"] = OUT_WEBP.stat().st_size
    print(f"  main {img.width}x{img.height} -> {info['webp']:,} B")
    prev = img.copy(); prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_PREV, "WEBP", quality=85, method=6); info["prev"] = OUT_PREV.stat().st_size
    print(f"  preview {prev.width}x{prev.height} -> {info['prev']:,} B")

    print("\n[2/3] Storage")
    put(BUCKET, IMG_REMOTE, OUT_WEBP, "image/webp")
    put(BUCKET, PREV_REMOTE, OUT_PREV, "image/webp")

    print("\n[3/3] INSERT Postgres + FCM")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'ANIME'::wallpaper_category, %s,
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
    """, (
        WALL_ID, "Pokemon · Cafecito en casa",
        "Pikachu tomando cafecito junto a la chimenea — escena cozy con lluvia y libreros",
        TAGS, IMG_REMOTE, PREV_REMOTE, info["webp"], info["prev"], GLOW,
        next_sort, "Pixora Studio", info["w"], info["h"]
    ))
    print(f"  upserted: {cur.fetchone()[0]}")
    conn.commit(); cur.close(); conn.close()

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  FCM wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print(f"\nPokemon static publicado · {info['w']}x{info['h']} · ANIME")

if __name__ == "__main__":
    main()
