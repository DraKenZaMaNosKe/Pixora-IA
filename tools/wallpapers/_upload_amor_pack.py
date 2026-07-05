"""Amor pack v1 — 6 static wallpapers for the new Amor tab (skin Latido).

Eduardo's first pack (2026-07-05). The two `panoramico_*` files in the same
folder were discarded: they are vertical 1080x1920 with white bands, not real
4192x1024 panoramics. Images keep their native 1080x1920 — resizing to the
1080x2340 target would stretch them; the app cover-fits.
"""
import re
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/amor")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_amor_pack")
BUCKET = "wallpaper-images"

# (src filename, wall id, name, description, category, glow, tags)
PACK = [
    (
        "corazon_de_amor_neon.png",
        "amor_corazon_neon",
        "Corazón de Neón",
        "Humo rosa y turquesa formando un corazón sobre una noche estrellada",
        "ART",
        "#FF4FB0",
        ["amor", "corazon", "neon", "noche", "estrellas", "humo"],
    ),
    (
        "gatito_amor.png",
        "amor_gatito_enamorado",
        "Gatito Enamorado",
        "Gatito naranja con moño rosa alcanzando un corazón brillante bajo la luna",
        "ANIMALS",
        "#FFB86B",
        ["amor", "gatito", "corazon", "luna", "kawaii", "rosas"],
    ),
    (
        "gatitos_amorosos_abrazados.png",
        "amor_gatitos_abrazados",
        "Gatitos Abrazados",
        "Dos gatitos abrazados formando un corazón con sus colas entre luces doradas",
        "ANIMALS",
        "#FFC46B",
        ["amor", "gatitos", "abrazo", "corazon", "kawaii", "bokeh"],
    ),
    (
        "kiss_japon.png",
        "amor_beso_japon",
        "Beso en Japón",
        "Pareja de anime besándose entre luces bokeh moradas y doradas de noche",
        "ANIME",
        "#B07CFF",
        ["amor", "anime", "pareja", "beso", "noche", "bokeh", "japon"],
    ),
    (
        "pareja_abrazada_en_el_mar.png",
        "amor_abrazo_atardecer",
        "Abrazo al Atardecer",
        "Silueta de una pareja abrazada junto al lago bajo un atardecer con luna creciente",
        "ANIME",
        "#FF7A45",
        ["amor", "pareja", "atardecer", "lago", "silueta", "montanas"],
    ),
    (
        "pareja_enamorada.png",
        "amor_noche_corazones",
        "Noche de Corazones",
        "Pareja junto a un auto clásico bajo la luna llena en un campo de flores y corazones",
        "ANIME",
        "#FFD36B",
        ["amor", "pareja", "luna", "corazones", "flores", "noche", "auto"],
    ),
]


def load_service_key():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_service_key()


def put(remote, local, ct="image/webp"):
    body = local.read_bytes()
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
        data=body, method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=60) as r:
        print(f"  PUT {BUCKET}/{remote} -> {r.status} ({len(body):,} B)")


def main():
    from PIL import Image

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect

    WORK.mkdir(parents=True, exist_ok=True)
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]

    for i, (fname, wid, name, desc, cat, glow, tags) in enumerate(PACK):
        src = SRC_DIR / fname
        if not src.exists():
            raise SystemExit(f"No existe {src}")
        print(f"\n[{i + 1}/{len(PACK)}] {wid}")

        img = Image.open(src).convert("RGB")
        out_webp = WORK / f"{wid}.webp"
        out_prev = WORK / f"{wid}_preview.webp"
        img.save(out_webp, "WEBP", quality=90, method=6)
        prev = img.copy()
        prev.thumbnail((540, 1170), Image.LANCZOS)
        prev.save(out_prev, "WEBP", quality=85, method=6)
        print(f"  main {img.width}x{img.height} -> {out_webp.stat().st_size:,} B"
              f" · preview {prev.width}x{prev.height} -> {out_prev.stat().st_size:,} B")

        put(f"{wid}.webp", out_webp)
        put(f"{wid}_preview.webp", out_prev)

        cur.execute(
            """
            INSERT INTO wallpapers (
                id, name, description, type, category, tags,
                image_path, preview_path, image_size, preview_size,
                glow_color, badge, sort_order, featured, trending_score,
                published, daily_eligible, author_name, media_width, media_height
            ) VALUES (
                %s, %s, %s, 'static'::wallpaper_type, %s::wallpaper_category, %s,
                %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, false, 0,
                true, true, %s, %s, %s
            )
            ON CONFLICT (id) DO UPDATE SET
                name=EXCLUDED.name, description=EXCLUDED.description,
                category=EXCLUDED.category, tags=EXCLUDED.tags,
                image_path=EXCLUDED.image_path, preview_path=EXCLUDED.preview_path,
                image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
                glow_color=EXCLUDED.glow_color, badge=EXCLUDED.badge,
                published=EXCLUDED.published, daily_eligible=EXCLUDED.daily_eligible,
                media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
                updated_at=now()
            RETURNING id;
            """,
            (
                wid, name, desc, cat, tags,
                f"{wid}.webp", f"{wid}_preview.webp",
                out_webp.stat().st_size, out_prev.stat().st_size,
                glow, next_sort + i, "Pixora Studio",
                img.width, img.height,
            ),
        )
        print(f"  upserted: {cur.fetchone()[0]} · {cat} · sort {next_sort + i}")

    conn.commit()
    cur.close()
    conn.close()

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate

    print(f"\nFCM wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print(f"Amor pack v1 publicado · {len(PACK)} wallpapers · tag amor")


if __name__ == "__main__":
    main()
