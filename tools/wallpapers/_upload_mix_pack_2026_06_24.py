"""Mix Pack 7 — 2026-06-24 (Garfield + Ghibli x2 + Crash + Goku pano + Coraje + Ed Edd Eddy).

Skip de la versión con watermark ajeno (grok-97680bcc — tiene
'WSTAORAM · Maauricio' impreso). El resto se sube como anime/gaming.
"""
import re
import shutil
import sys
import urllib.request
from pathlib import Path

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
DL = Path(r"C:/Users/lalo/Downloads")
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/mix_pack_2026_06_24")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_mix_2026_06_24")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

WALLPAPERS = [
    {
        "id": "anime_garfield_cozy_sala",
        "src": "grok-7fca0a36-e124-4776-991f-ebf67ba329f6.jpg",
        "name": "Garfield · Sala Cozy",
        "description": "Garfield acostado en su sillón rosa con Odie durmiendo a sus pies. Comics, lasaña, reloj 9:16 y todo el confort domingero del gato más flojo del mundo.",
        "type": "static", "cat": "ANIME", "glow": "#FBBF24",
        "tags": ["anime", "garfield", "odie", "cartoon", "cozy", "sala", "sofa", "clasico"],
    },
    {
        "id": "anime_ghibli_mosaico_portrait",
        "src": "grok-7e980ecc-44f5-4cc9-b23c-f8b4fa27b23d.jpg",
        "name": "Mosaico Ghibli",
        "description": "Totoro, Sin Cara, Chihiro, Howl, Mononoke, Kiki, Calcifer y muchos más reunidos en una composición épica con dragón blanco y castillo al fondo. Homenaje al universo Ghibli.",
        "type": "static", "cat": "ANIME", "glow": "#10B981",
        "tags": ["anime", "ghibli", "totoro", "spirited_away", "howl", "mosaico", "japones", "miyazaki"],
    },
    {
        "id": "gaming_crash_bandicoot_jungla",
        "src": "grok-9cf5547f-4f38-4d98-a3be-ceff580b3a7b.jpg",
        "name": "Crash · Salto en la Jungla",
        "description": "Crash Bandicoot saltando con las máscaras Aku Aku en pleno polvazo colorido de la jungla. Hojas tropicales, naranja explosivo y la energía del marsupial más icónico de PlayStation.",
        "type": "static", "cat": "GAMING", "glow": "#F97316",
        "tags": ["gaming", "crash_bandicoot", "playstation", "jungla", "platformer", "retro", "salto", "marsupial"],
    },
    {
        "id": "pano_goku_shenron_cielo",
        "src": "grok-af313f13-5ca6-4eb3-bd75-093c850b964d.jpg",
        "name": "Goku y Shenron en los Cielos",
        "description": "Goku niño volando en la Nube Voladora mientras Shenron emerge majestuoso entre las nubes doradas. Dragon Ball clásico en su forma más mística.",
        "type": "panoramic", "cat": "ANIME", "glow": "#22C55E",
        "tags": ["panoramica", "anime", "goku", "dragon_ball", "shenron", "nube_voladora", "nubes", "cielo"],
    },
    {
        "id": "anime_coraje_perro_cielo_rojo",
        "src": "grok-ba56801b-7377-465c-ba9e-32f1d100401a.jpg",
        "name": "Coraje · El Cielo Rojo",
        "description": "Coraje el Perro Cobarde temblando frente a la casa de Muriel mientras un cielo rojo carmesí se retuerce en el campo de Nowhere. La pesadilla cartoon clásica de Cartoon Network.",
        "type": "static", "cat": "ANIME", "glow": "#DC2626",
        "tags": ["anime", "coraje", "courage_dog", "cartoon_network", "horror", "perro", "cielo_rojo", "nowhere"],
    },
    {
        "id": "anime_ed_edd_eddy_gaming",
        "src": "grok-5ca01f8b-6476-4acf-bf5b-6a97ec144796.jpg",
        "name": "Ed, Edd y Eddy · Maratón Gaming",
        "description": "Los tres Eds en pijama y sofá viejo jugando consola con sonrisas pícaras. Latas, snacks regados y la cara icónica de cada uno — pure peak Cartoon Network.",
        "type": "static", "cat": "ANIME", "glow": "#3B82F6",
        "tags": ["anime", "ed_edd_eddy", "cartoon_network", "gaming", "sofa", "amigos", "noventero", "videojuegos"],
    },
    {
        "id": "pano_ghibli_mosaico_colina",
        "src": "grok-e348715e-67ab-42f7-8018-35222b5bde4e.jpg",
        "name": "Reunión Ghibli en la Colina",
        "description": "Totoro, Sin Cara, Howl, Mononoke y compañía reunidos en una colina verde con el castillo de Howl flotando al fondo. Panorámica épica del universo Ghibli en formato wide.",
        "type": "panoramic", "cat": "ANIME", "glow": "#84CC16",
        "tags": ["panoramica", "anime", "ghibli", "totoro", "howl", "miyazaki", "japones", "colina"],
    },
]


def put(remote, body, ct="image/webp"):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
        data=body, method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"    PUT {remote} -> {r.status} ({len(body):,} B)")


def encode_full(src, dst, q=88):
    img = Image.open(src).convert("RGB")
    img.save(dst, "WEBP", quality=q, method=6)
    return dst.read_bytes(), img


def encode_preview(src, dst, is_pano, q=85):
    max_side = 720 if is_pano else 540
    img = Image.open(src).convert("RGB")
    img.thumbnail((max_side, max_side * 2), Image.LANCZOS)
    img.save(dst, "WEBP", quality=q, method=6)
    return dst.read_bytes()


print("=" * 60)
print(f"Mix Pack — {len(WALLPAPERS)} wallpapers (6 static + 2 pano)")
print("=" * 60)

conn = connect()
cur = conn.cursor()

for w in WALLPAPERS:
    src = DL / w["src"]
    if not src.exists():
        print(f"\n[SKIP] {w['id']}: NO existe {src.name}")
        continue
    print(f"\n[{w['type'].upper()}/{w['cat']}] {w['id']}  {w['name']}")
    shutil.copy2(src, BACKUP / w["src"])

    full_remote = f"{w['id']}.webp"
    prev_remote = f"{w['id']}_preview.webp"
    full_body, img = encode_full(src, WORK / full_remote)
    prev_body = encode_preview(src, WORK / prev_remote, w["type"] == "panoramic")
    put(full_remote, full_body)
    put(prev_remote, prev_body)

    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    sort = cur.fetchone()[0]

    cur.execute(
        f"""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name,
            media_width, media_height
        ) VALUES (
            %s, %s, %s, '{w['type']}'::wallpaper_type,
            '{w['cat']}'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s,
            false, 0, true, true, 'Pixora Studio', %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description,
            tags=EXCLUDED.tags, image_path=EXCLUDED.image_path,
            preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color,
            type=EXCLUDED.type, category=EXCLUDED.category,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            updated_at=now()
        RETURNING id, sort_order;
        """,
        (
            w["id"], w["name"], w["description"], w["tags"],
            full_remote, prev_remote, len(full_body), len(prev_body),
            w["glow"], sort, img.width, img.height,
        ),
    )
    rid, rsort = cur.fetchone()
    print(f"    postgres: {rid}  sort={rsort}  {img.width}x{img.height}")

conn.commit()
cur.close()
conn.close()

print("\n[FCM]")
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _fcm_push import send_catalog_invalidate
print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")
print(f"\n[OK] {len(WALLPAPERS)} wallpapers publicados")
