"""Pack PANORAMIC — paisajes 2026-07-04 (batch 2 de 8 imagenes).

8 paisajes mas — mitologia + anime Ghibli/Shinkai style.
Grok 16:9 (1792x1008), Pixora los detecta como panoramicos y
paneara horizontalmente en el home screen.
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
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/paisages")
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/paisages_uploaded_2026_07_04")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_paisages_batch2")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

WALLPAPERS = [
    {
        "id": "pano_castillo_cielo_laputa",
        "src": "ciudadenelcielo_.jpg",
        "name": "Castillo Flotante en el Cielo",
        "description": "Ciudad-castillo suspendida sobre mar de nubes al atardecer con arquitectura gotica en bronce y cobre. Dirigibles rodeando la fortaleza y un guardian robotico solitario en jardin terraza — homenaje a Laputa.",
        "glow": "#F59E0B",
        "tags": ["paisaje", "panoramica", "anime", "laputa", "castillo", "nubes", "ghibli", "steampunk"],
    },
    {
        "id": "pano_escuela_entre_nubes",
        "src": "escuela_entrenubes.jpg",
        "name": "Escuela sobre el Mar de Nubes",
        "description": "Escuela tradicional japonesa en un acantilado con vista al infinito mar de nubes al amanecer. Cerezos en flor, grullas volando entre nubes y silueta de estudiante contemplativa — estilo Makoto Shinkai.",
        "glow": "#F9A8D4",
        "tags": ["paisaje", "panoramica", "anime", "shinkai", "escuela", "nubes", "amanecer", "cerezos"],
    },
    {
        "id": "pano_maya_medianoche_kukulcan",
        "src": "maya_medianoche_kukulcan.jpg",
        "name": "Ciudad Maya a Medianoche",
        "description": "Ciudad maya oculta en la selva de Yucatan durante alineacion ceremonial. Templo de Kukulcan iluminado por antorchas con columna de luna cayendo exacta sobre su cima. Jaguar acechando, luciernagas y Via Lactea sobre el cielo.",
        "glow": "#7C3AED",
        "tags": ["paisaje", "panoramica", "mitologia", "maya", "kukulcan", "yucatan", "medianoche", "jungla"],
    },
    {
        "id": "pano_olimpo_griego",
        "src": "olimpo.jpg",
        "name": "Monte Olimpo con Titan",
        "description": "Monte Olimpo elevandose sobre mar de nubes al golden hour. Complejo de templos de marmol en la cima, silueta de titan encadenado colosal en el horizonte, Pegaso volando y rayos de sol atravesando nubes doradas.",
        "glow": "#FBBF24",
        "tags": ["paisaje", "panoramica", "mitologia", "olimpo", "griego", "titan", "pegaso", "epico"],
    },
    {
        "id": "pano_pueblo_ghibli_molino",
        "src": "pueblo_glibli.jpg",
        "name": "Pueblo Ghibli con Molino",
        "description": "Colinas verdes onduladas con molino tradicional y pequenio pueblo junto al rio. Sol poniendose detras de las montanas iluminando campos de lavanda morada y colza amarilla. Estilo pictorico Studio Ghibli, Kazuo Oga.",
        "glow": "#84CC16",
        "tags": ["paisaje", "panoramica", "anime", "ghibli", "pueblo", "molino", "colinas", "atardecer"],
    },
    {
        "id": "pano_santuario_amaterasu",
        "src": "santuario_amaterasu.jpg",
        "name": "Santuario de Amaterasu al Amanecer",
        "description": "Complejo de santuario sintoista en la cima de la montania exactamente al amanecer. La diosa Amaterasu emerge del torii de piedra como luz dorada pura irradiando en abanico. Petalos de cerezo suspendidos capturando la luz.",
        "glow": "#FDE047",
        "tags": ["paisaje", "panoramica", "mitologia", "japon", "amaterasu", "torii", "amanecer", "sintoista"],
    },
    {
        "id": "pano_tenochtitlan_quetzalcoatl",
        "src": "tenochtitlan_quetzalcoatl.jpg",
        "name": "Tenochtitlan con Quetzalcoatl",
        "description": "Tenochtitlan antigua al amanecer con chinampas flotantes sobre lago Texcoco. Templo Mayor recibiendo primera luz y Quetzalcoatl, la serpiente emplumada, enroscandose entre las nubes con plumaje iridiscente esmeralda-turquesa-carmesi.",
        "glow": "#10B981",
        "tags": ["paisaje", "panoramica", "mitologia", "azteca", "tenochtitlan", "quetzalcoatl", "mexica", "amanecer"],
    },
    {
        "id": "pano_torii_cerezos_flotante",
        "src": "torri_flotante.jpg",
        "name": "Torii en Rio de Cerezos",
        "description": "Torii bermellon colosal parado en rio poco profundo rodeado de cerezos en flor plena. Petalos rosas cayendo como lluvia y flotando en el agua, niebla matutina, koi bajo la superficie — estilo Shinkai.",
        "glow": "#DC2626",
        "tags": ["paisaje", "panoramica", "anime", "torii", "cerezos", "japon", "shinkai", "primavera"],
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
    img = Image.open(src).convert("RGB")
    img.thumbnail((max_side, max_side), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes()


print("=" * 60)
print(f"Pack PANORAMIC paisages batch 2 — {len(WALLPAPERS)} wallpapers")
print("=" * 60)

conn = connect()
cur = conn.cursor()

for w in WALLPAPERS:
    src = SRC_DIR / w["src"]
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

print(f"\n[OK] paisages batch 2 ({len(WALLPAPERS)}) publicado")
