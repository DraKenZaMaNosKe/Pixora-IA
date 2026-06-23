"""Pack PANORAMIC 10 — paisajes 16:9 (1792x1008) Grok.

10 paisajes ultra-wide para la sección PANORAMIC + Daily mode panorámico.
Estilo HDR + golden hour + pasteles, sin gente ni texto.
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
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/panoramic_pack10_2026_06_22")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_panoramic_pack10")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

WALLPAPERS = [
    {
        "id": "pano_playa_nube_corazon",
        "src": "grok-0302e7a1-3565-45da-a7c0-d8af30c347e5.jpg",
        "name": "Playa con Nube Corazón",
        "description": "Atardecer dramático sobre playa tropical con una nube en forma de corazón flotando sobre el sol. Reflejos dorados y rosa coral en la arena húmeda — postal HDR perfecta.",
        "glow": "#F97316",
        "tags": ["paisaje", "panoramica", "playa", "atardecer", "corazon", "nube", "tropical", "hdr"],
    },
    {
        "id": "pano_amapolas_bahia",
        "src": "grok-b42b8b10-0638-499f-9a50-9cfe173b86c0.jpg",
        "name": "Sendero de Amapolas hacia el Mar",
        "description": "Un sendero serpentea entre amapolas rojas y margaritas blancas hasta llegar a una bahía mediterránea iluminada por la luz dorada del atardecer. Pueblo costero a lo lejos.",
        "glow": "#DC2626",
        "tags": ["paisaje", "panoramica", "amapolas", "sendero", "bahia", "mediterraneo", "golden_hour", "flores"],
    },
    {
        "id": "pano_lago_camino_atardecer",
        "src": "grok-b80da1a6-ff96-4643-be18-6872887d3aaa.jpg",
        "name": "Camino al Lago al Atardecer",
        "description": "Un camino de tierra bordeado por cerca de madera serpentea junto a un lago espejado bajo un cielo naranja intenso. Bosque profundo y montañas en silueta — calma rural perfecta.",
        "glow": "#EA580C",
        "tags": ["paisaje", "panoramica", "lago", "camino", "cerca", "atardecer", "rural", "bosque"],
    },
    {
        "id": "pano_valle_alpino_flores",
        "src": "grok-47a7b51d-9ee4-42f9-9ef1-0156827fcdb4.jpg",
        "name": "Valle Alpino con Arroyo",
        "description": "Picos nevados iluminados por el sol alpenglow se elevan sobre una pradera de flores amarillas y fucsia mientras un arroyo cristalino baja serpenteando. Suiza en su máximo esplendor.",
        "glow": "#22C55E",
        "tags": ["paisaje", "panoramica", "alpes", "valle", "flores", "arroyo", "montana", "nieve"],
    },
    {
        "id": "pano_luna_enorme_acantilado",
        "src": "grok-0817a4c0-ae00-4022-8a95-0a24f3d4bdbe.jpg",
        "name": "Luna Llena sobre el Acantilado",
        "description": "Una luna gigante color miel se eleva detrás de pinos en silueta sobre un acantilado rocoso. Cielo azul profundo y franja naranja del atardecer — escena épica de fantasía real.",
        "glow": "#FBBF24",
        "tags": ["paisaje", "panoramica", "luna", "acantilado", "pinos", "noche", "epico", "rocas"],
    },
    {
        "id": "pano_lago_asters_morados",
        "src": "grok-56f322c9-0f4f-4c63-b576-d30917067413.jpg",
        "name": "Asters Morados al Anochecer",
        "description": "Un prado de asters morados se extiende hasta un lago espejado que refleja montañas nevadas bajo cielo violeta profundo. Hora azul mágica con tonos púrpura intenso.",
        "glow": "#8B5CF6",
        "tags": ["paisaje", "panoramica", "lago", "asters", "morado", "montana", "anochecer", "violeta"],
    },
    {
        "id": "pano_pasarela_bosque_otonal",
        "src": "grok-c3ce1fae-9c73-4d40-8e9d-17bbd8248fe0.jpg",
        "name": "Pasarela en Bosque de Otoño",
        "description": "Una pasarela de madera atraviesa un bosque de hayas en pleno otoño. Dosel dorado y naranja por todos lados, hojas alfombrando el suelo y rayos de sol cruzando el aire.",
        "glow": "#EA580C",
        "tags": ["paisaje", "panoramica", "pasarela", "bosque", "otono", "hojas", "rayos", "madera"],
    },
    {
        "id": "pano_playa_blue_hour_lavanda",
        "src": "grok-a440a4ac-ffa4-435b-9ebc-ecf89ddbea19.jpg",
        "name": "Playa en Hora Azul",
        "description": "Cielo pastel lavanda y rosa cubre una playa tropical en la hora azul, con una nube en forma de corazón flotando sobre el horizonte. Olas suaves y arena espejada — calma absoluta.",
        "glow": "#C4B5FD",
        "tags": ["paisaje", "panoramica", "playa", "blue_hour", "lavanda", "calma", "pastel", "corazon"],
    },
    {
        "id": "pano_lago_amanecer_niebla",
        "src": "grok-1e87c052-1087-41fd-ad70-062b9360a7b0.jpg",
        "name": "Amanecer con Niebla en el Lago",
        "description": "Niebla suave flota sobre la superficie quieta de un lago al amanecer mientras un camino con cerca de madera bordea la orilla. Cielo pastel rosa y melocotón sobre colinas brumosas.",
        "glow": "#FBCFE8",
        "tags": ["paisaje", "panoramica", "lago", "amanecer", "niebla", "pastel", "cerca", "calma"],
    },
    {
        "id": "pano_valle_alpino_arcoiris",
        "src": "grok-aa60f1e1-7d6c-4968-901a-54585ec5cde0.jpg",
        "name": "Arcoíris tras la Tormenta",
        "description": "Cielo dramático se abre tras la tormenta dejando un arcoíris doble sobre picos nevados. Un arroyo baja entre flores fucsia y verdes praderas alpinas — momento de luz épico.",
        "glow": "#A78BFA",
        "tags": ["paisaje", "panoramica", "arcoiris", "tormenta", "valle", "alpes", "epico", "flores"],
    },
]


def put(remote, body, ct="image/webp"):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
        data=body,
        method="PUT",
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


def encode_preview(src, dst, max_side=720, quality=82):
    """Panorámicas → preview más ancho (720 px) para que se vea bien
    en el card del grid."""
    img = Image.open(src).convert("RGB")
    img.thumbnail((max_side, max_side), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes()


print("=" * 60)
print(f"Pack PANORAMIC — {len(WALLPAPERS)} wallpapers 16:9 (1792x1008)")
print("=" * 60)

conn = connect()
cur = conn.cursor()

for w in WALLPAPERS:
    src = DL / w["src"]
    if not src.exists():
        print(f"\n[SKIP] {w['id']}: NO existe {src.name}")
        continue
    print(f"\n[PANO] {w['id']}  {w['name']}")
    shutil.copy2(src, BACKUP / w["src"])

    full_remote = f"{w['id']}.webp"
    prev_remote = f"{w['id']}_preview.webp"
    full_body, img = encode_full(src, WORK / full_remote)
    prev_body = encode_preview(src, WORK / prev_remote)
    put(full_remote, full_body)
    put(prev_remote, prev_body)

    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    sort = cur.fetchone()[0]

    cur.execute(
        """
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
            false, 0, true, true, 'Pixora Studio', %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description,
            tags=EXCLUDED.tags, image_path=EXCLUDED.image_path,
            preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            daily_eligible=true,
            category='PANORAMIC'::wallpaper_category,
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

print(f"\n[OK] PANORAMIC pack {len(WALLPAPERS)} publicado")
