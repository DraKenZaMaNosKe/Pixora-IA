"""Mix Pack 8 — anime + gaming + scifi (5 static + 3 panoramic).

Distribución por categoría según escena (no PAISAJES):
  · ANIME: Beerus, Finn&Jake, Coyote/Roadrunner, personajes_puerta, Adventure Time
  · GAMING: Pixel Palace Arcade, Zelda Link Master Sword
  · SCIFI: Wall-E con plantita
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
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/mix_pack8_2026_06_22")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_mix_pack8")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

WALLPAPERS = [
    # ── ANIME static ──
    {
        "id": "anime_beerus_trono_cosmico",
        "src": "grok-3d1c523a-5e48-4a8d-bfdb-293e00c051d2.jpg",
        "name": "Beerus en el Trono Cósmico",
        "description": "El Dios de la Destrucción sentado en su trono entre llamas violetas y cósmicas, sosteniendo una esfera de energía Hakai. Dragon Ball Super en su máxima presencia divina.",
        "type": "static", "cat": "ANIME", "glow": "#A855F7",
        "tags": ["anime", "beerus", "dragon_ball", "dios_destruccion", "fuego", "cosmos", "trono"],
    },
    {
        "id": "anime_finn_jake_estrellas",
        "src": "grok-f71d9d03-ac27-4df7-aca6-dab6a9e8537f.jpg",
        "name": "Finn y Jake bajo las Estrellas",
        "description": "Finn y Jake sentados en las escaleras observando un cielo estrellado con nubes esponjosas rosa. Una máquina expendedora neón les hace compañía en la noche perfecta.",
        "type": "static", "cat": "ANIME", "glow": "#F472B6",
        "tags": ["anime", "adventure_time", "finn", "jake", "estrellas", "noche", "cartoon", "chill"],
    },
    {
        "id": "anime_personajes_asomando_puerta",
        "src": "grok-f0778f6d-8a61-4f76-885a-b6fe09c7ea5c.jpg",
        "name": "Personajes Asomándose",
        "description": "Tus personajes animados favoritos se apilan curiosos asomándose por una puerta entreabierta con luz roja al fondo. Cinco caras icónicas en un solo wallpaper.",
        "type": "static", "cat": "ANIME", "glow": "#EF4444",
        "tags": ["anime", "personajes", "puerta", "cartoon", "pixar", "wholesome", "rojo"],
    },
    # ── ANIME panoramic ──
    {
        "id": "pano_coyote_correcaminos",
        "src": "grok-1ae3a739-138b-4112-a63b-bc84f0e3404f.jpg",
        "name": "Persecución en el Desierto",
        "description": "El coyote astuto y el correcaminos veloz cruzan el desierto en su eterna persecución, con polvo levantado y mesas rocosas al fondo. Clásico cartoon en pleno movimiento.",
        "type": "panoramic", "cat": "ANIME", "glow": "#FBBF24",
        "tags": ["panoramica", "anime", "coyote", "correcaminos", "desierto", "cartoon", "looney_tunes", "clasico"],
    },
    {
        "id": "pano_adventure_time_noche",
        "src": "grok-235458b9-3c21-4280-b9b3-2b4a2802dcda.jpg",
        "name": "Tierra de Ooo de Noche",
        "description": "Finn y Jake junto a la fogata frente a su casa árbol, con el Reino Helado a un lado y el Bosque de Hongos brillantes al otro. Adventure Time bajo luna llena.",
        "type": "panoramic", "cat": "ANIME", "glow": "#3B82F6",
        "tags": ["panoramica", "anime", "adventure_time", "finn", "jake", "noche", "fogata", "casa_arbol"],
    },
    # ── GAMING ──
    {
        "id": "gaming_zelda_master_sword",
        "src": "grok-fcd2aade-0422-44c6-855f-979300835495.jpg",
        "name": "Sacando la Master Sword",
        "description": "Link levanta la Master Sword del pedestal en el santuario sagrado, con haz de luz divina y hada Navi flotando. Pixel art tributo épico a Zelda.",
        "type": "static", "cat": "GAMING", "glow": "#06B6D4",
        "tags": ["gaming", "zelda", "link", "master_sword", "pixel_art", "templo", "trifuerza", "nintendo"],
    },
    {
        "id": "pano_pixel_palace_arcade",
        "src": "grok-d5faee33-2347-4cc6-99e9-98932880ce12.jpg",
        "name": "Pixel Palace Arcade",
        "description": "Calle nocturna lluviosa estilo cyberpunk Tokio con letreros neón rosa y púrpura del arcade Pixel Palace. Charcos reflejan luces 8-bit en la banqueta — synthwave gamer puro.",
        "type": "panoramic", "cat": "GAMING", "glow": "#EC4899",
        "tags": ["panoramica", "gaming", "arcade", "cyberpunk", "neon", "lluvia", "synthwave", "pixel_art", "tokio"],
    },
    # ── SCIFI ──
    {
        "id": "scifi_walle_plantita",
        "src": "grok-7fbd6cf7-a80b-4fa6-b29d-68465dd4fee7.jpg",
        "name": "Wall-E y la Plantita",
        "description": "Wall-E descubre con asombro una pequeña planta verde brillante entre escombros bajo cielo estrellado. Símbolo de esperanza en un planeta post-apocalíptico.",
        "type": "static", "cat": "SCIFI", "glow": "#84CC16",
        "tags": ["scifi", "walle", "robot", "plantita", "esperanza", "post_apocaliptico", "noche", "pixar"],
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


def encode_full(src, dst, quality=88):
    img = Image.open(src).convert("RGB")
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes(), img


def encode_preview(src, dst, is_pano, quality=85):
    max_side = 720 if is_pano else 540
    img = Image.open(src).convert("RGB")
    img.thumbnail((max_side, max_side * 2), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes()


print("=" * 60)
print(f"Mix Pack — {len(WALLPAPERS)} wallpapers (anime + gaming + scifi)")
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

print("\n" + "=" * 60)
print("FCM invalidate")
print("=" * 60)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _fcm_push import send_catalog_invalidate

print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")

print(f"\n[OK] Mix pack {len(WALLPAPERS)} publicado")
