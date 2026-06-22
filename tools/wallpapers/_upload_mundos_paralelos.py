"""
Pixora · Batch publisher — Mundos Paralelos Vol. I

Sube 5 panorámicas generadas con Grok (aspect 1.78:1 ≈ 16:9) como
nuevos wallpapers panorámicos. Cada uno es un "mundo" distinto al
nuestro pero igualmente habitable.

  1. Archipiélago de Cristal Flotante
  2. Bosque Bioluminiscente Eterno
  3. Ciudades de Latón en el Cielo
  4. Desierto de los Dos Soles
  5. Catedrales Abisales

Flujo (mismo patrón que _upload_rancho/_upload_tren):
  · WebP encoding del original JPG (q90 main, q82 preview)
  · PUT a wallpaper-images bucket (paths estables)
  · INSERT en public.wallpapers (type=panoramic, category=PANORAMIC)
  · FCM invalidate al topic 'wallpapers' al final
"""
from __future__ import annotations
import re, sys, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/mundos_paralelos")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_mundos")

WALLPAPERS = [
    {
        "id": "pano_archipielago_cristal",
        "src": "archipielago_cristal.jpg",
        "name": "Archipiélago de Cristal Flotante",
        "description": "Islas enormes de cristal translúcido suspendidas sobre un mar de niebla violeta — atardecer dorado permanente con auroras suaves y cascadas que caen al vacío.",
        "glow": "#C49A4E",
        "tags": ["archipielago", "cristal", "islas", "niebla", "violeta",
                 "atardecer", "aurora", "fantasy", "mundo_paralelo",
                 "mundos_paralelos", "panoramico"],
    },
    {
        "id": "pano_bosque_bioluminiscente",
        "src": "bosque_bioluminiscente.jpg",
        "name": "Bosque Bioluminiscente Eterno",
        "description": "Selva en crepúsculo perpetuo: hongos gigantes, lianas luminosas y un río que refleja luz teal y esmeralda. Partículas como luciérnagas flotan en el aire.",
        "glow": "#2DD4BF",
        "tags": ["bosque", "bioluminiscente", "hongos", "lianas",
                 "luciernagas", "magico", "selva", "fantasy",
                 "mundo_paralelo", "mundos_paralelos", "panoramico"],
    },
    {
        "id": "pano_ciudades_laton",
        "src": "ciudades_laton.jpg",
        "name": "Ciudades de Latón en el Cielo",
        "description": "Metrópolis steampunk victoriana sobre plataformas flotantes en un océano de nubes doradas — domos de bronce, torres de engranajes y dirigibles lejanos.",
        "glow": "#B8732A",
        "tags": ["ciudades", "laton", "steampunk", "victoriano",
                 "dirigible", "bronce", "cielo", "fantasy",
                 "mundo_paralelo", "mundos_paralelos", "panoramico"],
    },
    {
        "id": "pano_desierto_dos_soles",
        "src": "desierto_dos_soles.jpg",
        "name": "Desierto de los Dos Soles",
        "description": "Dunas infinitas bajo dos soles en horizontes opuestos — cielo ámbar y violeta, ruinas de piedra azul semienterradas y arcos de roca erosionados por el viento.",
        "glow": "#F4A949",
        "tags": ["desierto", "dos_soles", "dunas", "ambar", "ruinas",
                 "scifi", "mundo_paralelo", "mundos_paralelos", "panoramico"],
    },
    {
        "id": "pano_catedrales_abisales",
        "src": "catedrales_abisales.jpg",
        "name": "Catedrales Abisales",
        "description": "Mundo submarino con arquitectura de coral y cristal — rayos de luz descendiendo desde la superficie, peces luminosos y aguamarina profundo.",
        "glow": "#3AA8C9",
        "tags": ["catedrales", "submarino", "coral", "cristal",
                 "aguamarina", "peces", "profundo", "fantasy",
                 "mundo_paralelo", "mundos_paralelos", "panoramico"],
    },
]

AUTHOR = "Pixora Studio"


def load_sk():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_sk()


def put(bucket, remote, body, ct):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body, method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"    PUT {remote} -> {r.status} ({len(body):,} B)")


def main():
    from PIL import Image
    print("=" * 70)
    print("Mundos Paralelos Vol. I — batch publisher (5 panorámicas)")
    print("=" * 70)
    WORK.mkdir(parents=True, exist_ok=True)

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect
    conn = connect(); cur = conn.cursor()

    for w in WALLPAPERS:
        src = SRC_DIR / w["src"]
        if not src.exists():
            print(f"\n[SKIP] {w['id']}: no existe {src}")
            continue
        print(f"\n[{w['id']}]  {w['name']}")
        img = Image.open(src).convert("RGB")
        print(f"    source {img.width}x{img.height}  aspect {img.width/img.height:.2f}:1")

        # Encode WebP full + preview
        full_remote = f"{w['id']}.webp"
        prev_remote = f"{w['id']}_preview.webp"
        full_path = WORK / full_remote
        prev_path = WORK / prev_remote

        img.save(full_path, "WEBP", quality=90, method=6)
        full_bytes = full_path.read_bytes()

        prev = img.copy()
        prev.thumbnail((1080, 1080), Image.LANCZOS)
        prev.save(prev_path, "WEBP", quality=82, method=6)
        prev_bytes = prev_path.read_bytes()

        put("wallpaper-images", full_remote, full_bytes, "image/webp")
        put("wallpaper-images", prev_remote, prev_bytes, "image/webp")

        # INSERT/UPSERT en postgres
        cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
        next_sort = cur.fetchone()[0]
        cur.execute("""
            INSERT INTO wallpapers (
                id, name, description, type, category, tags,
                image_path, preview_path, image_size, preview_size,
                glow_color, badge, sort_order, featured, trending_score,
                published, daily_eligible, author_name,
                media_width, media_height
            ) VALUES (
                %s, %s, %s, 'panoramic'::wallpaper_type,
                'PANORAMIC'::wallpaper_category, %s,
                %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s,
                false, 0, true, true, %s, %s, %s
            )
            ON CONFLICT (id) DO UPDATE SET
                name=EXCLUDED.name, description=EXCLUDED.description,
                tags=EXCLUDED.tags, image_path=EXCLUDED.image_path,
                preview_path=EXCLUDED.preview_path,
                image_size=EXCLUDED.image_size,
                preview_size=EXCLUDED.preview_size,
                glow_color=EXCLUDED.glow_color,
                media_width=EXCLUDED.media_width,
                media_height=EXCLUDED.media_height,
                updated_at=now()
            RETURNING id, sort_order;
        """, (
            w["id"], w["name"], w["description"], w["tags"],
            full_remote, prev_remote,
            len(full_bytes), len(prev_bytes),
            w["glow"], next_sort, AUTHOR,
            img.width, img.height,
        ))
        rid, rsort = cur.fetchone()
        print(f"    postgres: {rid}  sort_order={rsort}")
    conn.commit(); cur.close(); conn.close()

    # FCM al final (un solo invalidate cubre todo el batch)
    print("\n[FCM] invalidate topic wallpapers")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"    -> {send_catalog_invalidate('wallpapers')}")

    print("\n" + "=" * 70)
    print(f"Publicados {len(WALLPAPERS)} mundos paralelos")
    print("=" * 70)


if __name__ == "__main__":
    main()
