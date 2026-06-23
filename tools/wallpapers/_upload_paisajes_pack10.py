"""Pack PAISAJES 10 — daily-eligible landscapes 9:16 (1008x1792).

10 paisajes Grok seleccionados por Eduardo para rotar en Pixora Daily
modo PAISAJES. Estilo fotografía natural, sin gente ni texto, calma +
color + buen gusto. Categoría PAISAJES + daily_eligible=true.
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
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/paisajes_pack10_2026_06_22")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_paisajes_pack10")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

WALLPAPERS = [
    {
        "id": "paisaje_valle_montana_amanecer",
        "src": "grok-3eef2a9c-cfc2-4ff2-ae47-43d5f9b4ac46.jpg",
        "name": "Valle de Montaña al Amanecer",
        "description": "Niebla dorada cubre las capas de montañas mientras la luz cálida del amanecer asoma sobre los picos. Flores silvestres en primer plano — lavanda, margaritas y amarillo solar — añaden vida al silencio del valle.",
        "glow": "#F4A261",
        "tags": ["paisaje", "montana", "niebla", "amanecer", "flores", "valle", "relajante", "natural"],
    },
    {
        "id": "paisaje_playa_tropical_atardecer",
        "src": "grok-01e8005d-0b67-4be5-b5a1-fb65b46eb998.jpg",
        "name": "Playa Tropical al Atardecer",
        "description": "Agua turquesa cristalina lame la arena blanca mientras el sol se hunde en el horizonte tiñendo el cielo de rosa y coral. Palmeras en silueta cierran la escena perfecta de paz tropical.",
        "glow": "#FF8FA3",
        "tags": ["paisaje", "playa", "tropical", "atardecer", "palmeras", "mar", "turquesa", "relajante"],
    },
    {
        "id": "paisaje_lagos_alpinos_nieve",
        "src": "grok-13c5d753-110d-48d8-a433-53123501b2cc.jpg",
        "name": "Lagos Alpinos con Nieve",
        "description": "Picos nevados se reflejan perfectos en el agua quieta de un lago alpino. Pinos cargados de nieve enmarcan la escena en tonos fríos azul y plata — silencio absoluto de alta montaña.",
        "glow": "#7DD3FC",
        "tags": ["paisaje", "lago", "alpino", "nieve", "montana", "reflejo", "frio", "sereno"],
    },
    {
        "id": "paisaje_rio_bosque_otonal",
        "src": "grok-6dcae2c0-e25d-47b2-b113-26f3673cb43c.jpg",
        "name": "Río en Bosque Otoñal",
        "description": "Hojas amarillas, naranjas y rojas estallan en cada rama del bosque mientras un río cristalino fluye sobre piedras cubiertas de musgo. El otoño en su máxima expresión.",
        "glow": "#EA580C",
        "tags": ["paisaje", "rio", "bosque", "otono", "hojas", "musgo", "naturaleza", "relajante"],
    },
    {
        "id": "paisaje_colinas_verdes_roble",
        "src": "grok-f3a18358-282e-41d5-8174-f79a92f3726c.jpg",
        "name": "Roble Solitario entre Colinas",
        "description": "Un roble centenario se alza sobre colinas verde esmeralda mientras la niebla matinal serpentea entre los pliegues del paisaje. Escena idílica de Toscana o campo inglés.",
        "glow": "#84CC16",
        "tags": ["paisaje", "colinas", "roble", "niebla", "verde", "idilico", "campo", "natural"],
    },
    {
        "id": "paisaje_lago_muelle_atardecer",
        "src": "grok-a6ca5dcd-004a-464b-8c5d-33ca8efd5a84.jpg",
        "name": "Muelle al Atardecer",
        "description": "Un muelle de madera se extiende sobre un lago espejado al atardecer. Cielo cálido naranja y rosa, montañas oscuras en silueta y reflejo perfecto en el agua — calma pura.",
        "glow": "#F59E0B",
        "tags": ["paisaje", "lago", "muelle", "atardecer", "reflejo", "madera", "relajante", "montana"],
    },
    {
        "id": "paisaje_via_lactea_desierto",
        "src": "grok-eb199b36-1612-4e3e-a12b-ec4e3e758135.jpg",
        "name": "Vía Láctea sobre el Desierto",
        "description": "El arco completo de la Vía Láctea se eleva púrpura y dorado sobre badlands erosionadas del desierto. Miles de estrellas iluminan el cosmos — la inmensidad del universo en pantalla.",
        "glow": "#7C3AED",
        "tags": ["paisaje", "via_lactea", "desierto", "noche", "estrellas", "cosmos", "wow", "astronomia"],
    },
    {
        "id": "paisaje_bosque_bambu_rayos",
        "src": "grok-3c06d85b-716d-40ba-ac77-339ecfaf0076.jpg",
        "name": "Bosque de Bambú al Amanecer",
        "description": "Rayos de luz dorada cortan en diagonal entre los troncos altos de un bosque de bambú. Un sendero suave invita al paseo — zen puro estilo Kioto.",
        "glow": "#65A30D",
        "tags": ["paisaje", "bambu", "bosque", "rayos", "zen", "sendero", "japones", "verde"],
    },
    {
        "id": "paisaje_acantilado_mar_stacks",
        "src": "grok-2b53839c-50e8-42d5-af6c-41a5e324720e.jpg",
        "name": "Acantilados y Arcoíris",
        "description": "Mar agitado choca contra stacks rocosos mientras un arcoíris brillante atraviesa cielo de tormenta. Flores silvestres en el acantilado contrastan con la furia del Atlántico.",
        "glow": "#0EA5E9",
        "tags": ["paisaje", "acantilado", "mar", "stacks", "arcoiris", "dramatico", "olas", "tormenta"],
    },
    {
        "id": "paisaje_lavanda_blue_hour",
        "src": "grok-939a9f82-ba7e-44e4-ad46-cae0154ec821.jpg",
        "name": "Campos de Lavanda al Anochecer",
        "description": "Hileras infinitas de lavanda en flor convergen hacia una casa de campo solitaria con cipreses. Hora azul provenzal — púrpura profundo bajo cielo de transición.",
        "glow": "#8B5CF6",
        "tags": ["paisaje", "lavanda", "campos", "provenza", "blue_hour", "purpura", "casa", "suave"],
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


def encode_full(src, dst, quality=90):
    img = Image.open(src).convert("RGB")
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes(), img


def encode_preview(src, dst, max_side=540, quality=85):
    img = Image.open(src).convert("RGB")
    img.thumbnail((max_side, max_side * 2), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.read_bytes()


print("=" * 60)
print(f"Pack PAISAJES — {len(WALLPAPERS)} wallpapers daily-eligible")
print("=" * 60)

conn = connect()
cur = conn.cursor()

for w in WALLPAPERS:
    src = DL / w["src"]
    if not src.exists():
        print(f"\n[SKIP] {w['id']}: NO existe {src.name}")
        continue
    print(f"\n[STATIC] {w['id']}  {w['name']}")
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
            %s, %s, %s, 'static'::wallpaper_type,
            'PAISAJES'::wallpaper_category, %s,
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
            category='PAISAJES'::wallpaper_category,
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

print(f"\n[OK] PAISAJES pack {len(WALLPAPERS)} publicado")
