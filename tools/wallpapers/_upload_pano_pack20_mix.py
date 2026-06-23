"""Pack PANORAMIC 20 — mix paisajismo + variantes (fantasy/horror/anime/pixel/MX).

Por decisión Eduardo 2026-06-22: TODAS van con category=PAISAJES
(principal) + daily_eligible=true. Los tags secundarios (horror, fantasy,
anime, pixel, mexicana) permiten que aparezcan en su sección semántica
correspondiente vía tag-query (no por enum category).
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
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/pano_pack20_mix_2026_06_22")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_pano_pack20_mix")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

WALLPAPERS = [
    {
        "id": "pano_bosque_hongos_magicos",
        "src": "grok-13045fe1-c882-4226-bdfc-2f8594d516e3.jpg",
        "name": "Bosque de Hongos Mágicos",
        "description": "Un sendero serpentea entre hongos gigantes bioluminiscentes que brillan en azul, púrpura y rosa. Hadas voladoras y estrellas pixel iluminan la noche — fantasía pura.",
        "glow": "#A78BFA",
        "tags": ["paisaje", "panoramica", "fantasy", "hongos", "magico", "noche", "pixel_art", "bioluminiscente"],
    },
    {
        "id": "pano_luna_gigante_barquito",
        "src": "grok-76e83159-6088-440a-9f51-7811de519969.jpg",
        "name": "Luna Llena sobre el Mar",
        "description": "Una luna gigante de plata se eleva sobre un mar tranquilo mientras un barquito solitario navega bajo su luz reflejada. Calma absoluta del océano nocturno.",
        "glow": "#E5E7EB",
        "tags": ["paisaje", "panoramica", "luna", "mar", "noche", "barco", "calma", "solitario"],
    },
    {
        "id": "pano_lago_alpino_reflejo_perfecto",
        "src": "grok-73e7e9af-5e20-42a5-8902-6fcf0afad256.jpg",
        "name": "Lago Alpino — Reflejo Perfecto",
        "description": "Picos nevados se duplican en el espejo perfecto de un lago alpino mientras flores fucsia y amarillas adornan la orilla. Suiza fotográfica en su máxima claridad.",
        "glow": "#06B6D4",
        "tags": ["paisaje", "panoramica", "lago", "alpes", "reflejo", "montana", "nieve", "flores"],
    },
    {
        "id": "pano_pueblo_mx_papel_picado",
        "src": "grok-9160b854-3b16-44ed-a143-98266779ef9d.jpg",
        "name": "Pueblo Mexicano en Fiesta",
        "description": "Casitas multicolor en ladera mexicana con papel picado colgando entre tejados al atardecer. Calor de pueblo, raíces y celebración — México puro.",
        "glow": "#FB923C",
        "tags": ["paisaje", "panoramica", "mexico", "pueblo", "papel_picado", "fiesta", "atardecer", "cultura", "mexicana"],
    },
    {
        "id": "pano_calle_victoriana_pixel",
        "src": "grok-3805dba9-4255-4acf-ab88-c63ffc3d4968.jpg",
        "name": "Calle Victoriana en Niebla",
        "description": "Calle empedrada victoriana cubierta de niebla densa con farola encendida y catedral oscura al fondo. Pixel art atmosférico estilo aventura clásica.",
        "glow": "#6B7280",
        "tags": ["paisaje", "panoramica", "victoriano", "niebla", "pixel_art", "calle", "horror", "noche", "gotico"],
    },
    {
        "id": "pano_girasoles_tormenta",
        "src": "grok-67cb3ac7-e31e-4bb9-bbc1-17774fd07248.jpg",
        "name": "Girasoles bajo Tormenta",
        "description": "Campo extenso de girasoles inclinados por la lluvia bajo nubes gris plomo. Belleza melancólica de la naturaleza ante el clima — emocional y crudo.",
        "glow": "#FCD34D",
        "tags": ["paisaje", "panoramica", "girasoles", "tormenta", "lluvia", "campo", "dark", "melancolico"],
    },
    {
        "id": "pano_pueblo_pixel_montanas",
        "src": "grok-f9fa0e90-adbf-431f-8ba9-5192b037331f.jpg",
        "name": "Pueblo Pixel en el Valle",
        "description": "Un pueblo medieval pixel art descansa en valle verde rodeado de montañas nevadas. Nubes esponjosas en cielo azul — estética RPG retro clásica.",
        "glow": "#22C55E",
        "tags": ["paisaje", "panoramica", "pixel_art", "pueblo", "valle", "montana", "rpg", "retro", "medieval"],
    },
    {
        "id": "pano_capilla_swamp_gotico",
        "src": "grok-91391882-e782-4e1d-bac7-bf3849aaaeec.jpg",
        "name": "Capilla del Pantano",
        "description": "Capilla abandonada de madera entre pantano cubierto de niebla y árboles muertos. Atmósfera gótica de bayou — silencio cargado y luz verde plomo.",
        "glow": "#84CC16",
        "tags": ["paisaje", "panoramica", "capilla", "pantano", "niebla", "abandonado", "horror", "gotico", "swamp"],
    },
    {
        "id": "pano_islas_flotantes_cristales",
        "src": "grok-5bd76691-3830-4193-b6d5-53969fe01854.jpg",
        "name": "Islas Flotantes de Cristal",
        "description": "Islas mágicas flotan entre nubes rosa y naranja, cubiertas de cristales brillantes y cascadas doradas. Pajaritos kawaii y estrellas felices completan el cielo de fantasía.",
        "glow": "#F472B6",
        "tags": ["paisaje", "panoramica", "fantasy", "islas_flotantes", "cristales", "magico", "kawaii", "cielo"],
    },
    {
        "id": "pano_arbol_solitario_tormenta",
        "src": "grok-860e6c3b-a831-4511-a2de-ffe24b57cecb.jpg",
        "name": "Árbol Solitario bajo Tormenta",
        "description": "Un árbol solitario resiste en pradera de margaritas mientras nubes negras descargan lluvia en el horizonte. Belleza melancólica de la naturaleza salvaje.",
        "glow": "#475569",
        "tags": ["paisaje", "panoramica", "arbol", "tormenta", "pradera", "solitario", "dark", "dramatico"],
    },
    {
        "id": "pano_picnic_anime_molino",
        "src": "grok-9e0c8a7a-8b9d-45a3-8637-d6aed740aaef.jpg",
        "name": "Picnic en la Pradera",
        "description": "Cuatro amigos disfrutan un picnic anime en pradera florida con molino de viento al fondo. Mariposas y flores multicolores — felicidad estilo Ghibli.",
        "glow": "#FBBF24",
        "tags": ["paisaje", "panoramica", "anime", "picnic", "pradera", "molino", "amigos", "chill", "felicidad"],
    },
    {
        "id": "pano_muelle_otono_sillas",
        "src": "grok-388b5e30-a099-40f5-a073-3dbe246169f8.jpg",
        "name": "Muelle de Otoño",
        "description": "Dos sillas Adirondack vacías al final de un muelle de madera cubierto de hojas naranjas. Lago gris y bosque otoñal en día nublado — chill total.",
        "glow": "#F97316",
        "tags": ["paisaje", "panoramica", "muelle", "otono", "lago", "sillas", "chill", "nublado", "madera"],
    },
    {
        "id": "pano_aurora_fogata_pixel",
        "src": "grok-ceecdd72-1896-4488-b8e9-140dbd95c663.jpg",
        "name": "Aurora Boreal junto a la Fogata",
        "description": "Una fogata calienta la noche mientras la aurora boreal verde y púrpura danza sobre montañas nevadas reflejadas en el lago. Pixel art estilo ártico mágico.",
        "glow": "#10B981",
        "tags": ["paisaje", "panoramica", "aurora_boreal", "pixel_art", "fogata", "montana", "noche", "artico", "magico"],
    },
    {
        "id": "pano_hospital_abandonado_niebla",
        "src": "grok-51ed55d9-9f77-495c-8881-24b958b75966.jpg",
        "name": "Hospital Abandonado",
        "description": "Hospital soviético abandonado emerge de la niebla densa al final de una carretera cuarteada. Silencio post-apocalíptico — atmósfera Chernobyl inquietante.",
        "glow": "#6B7280",
        "tags": ["paisaje", "panoramica", "abandonado", "hospital", "niebla", "horror", "post_apocaliptico", "urbex"],
    },
    {
        "id": "pano_estacion_lluvia_anime",
        "src": "grok-6bf8781b-0669-4fe1-a2f3-082e61cf5982.jpg",
        "name": "Estación bajo la Lluvia",
        "description": "Estación de tren vacía con paraguas azul abierto, banca solitaria y skyline de ciudad anime al atardecer bajo lluvia. Lofi nostálgico estilo Makoto Shinkai.",
        "glow": "#3B82F6",
        "tags": ["paisaje", "panoramica", "anime", "lluvia", "estacion", "lofi", "ciudad", "atardecer", "nostalgico"],
    },
    {
        "id": "pano_torii_luna_roja",
        "src": "grok-256a3833-3d35-4241-995e-70c14f47d51f.jpg",
        "name": "Torii bajo la Luna de Sangre",
        "description": "Torii japonés ruinoso bajo luna roja de sangre rodeado de árboles muertos y luciérnagas púrpuras. Atmósfera de horror japonés clásico.",
        "glow": "#DC2626",
        "tags": ["paisaje", "panoramica", "torii", "japon", "luna_roja", "horror", "noche", "gotico", "japones"],
    },
    {
        "id": "pano_playa_arcoiris_rayos",
        "src": "grok-bf0878e7-aa4b-4395-807b-74bf05cbffcb.jpg",
        "name": "Playa con Arcoíris",
        "description": "Arcoíris doble brilla sobre playa tropical de arena blanca y agua turquesa cristalina. Palmeras al lado, sol radiante y promesa de día perfecto en el paraíso.",
        "glow": "#0EA5E9",
        "tags": ["paisaje", "panoramica", "playa", "arcoiris", "tropical", "palmera", "turquesa", "paraiso"],
    },
    {
        "id": "pano_playa_pixel_synthwave",
        "src": "grok-db50f51d-c90b-490b-9486-48e7b2f862ed.jpg",
        "name": "Playa Pixel Synthwave",
        "description": "Atardecer pixel art naranja y púrpura sobre playa tropical con palmeras en silueta y templos antiguos en la costa. Estética synthwave 16-bit retro.",
        "glow": "#F97316",
        "tags": ["paisaje", "panoramica", "pixel_art", "playa", "synthwave", "atardecer", "tropical", "retro"],
    },
    {
        "id": "pano_valle_sakura_anime",
        "src": "grok-07386a99-78d7-4ddd-a631-85cfb9cdf672.jpg",
        "name": "Valle de Cerezos en Flor",
        "description": "Cerezos sakura en plena floración rosa dejan caer pétalos sobre valle anime con río brillante. Cielo azul con nubes esponjosas — primavera japonesa idealizada.",
        "glow": "#FBCFE8",
        "tags": ["paisaje", "panoramica", "anime", "sakura", "cerezos", "valle", "primavera", "rio", "japones"],
    },
    {
        "id": "pano_arbol_colina_rayos",
        "src": "grok-605fd3cf-8dee-4ba7-a879-85878947705c.jpg",
        "name": "Rayos sobre el Árbol Solitario",
        "description": "Rayos de sol divinos atraviesan nubes tormentosas iluminando un árbol solitario en colina de margaritas blancas. Composición épica y emocional.",
        "glow": "#94A3B8",
        "tags": ["paisaje", "panoramica", "arbol", "rayos", "tormenta", "colina", "margaritas", "epico", "dramatico"],
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
print(f"Pack PANORAMIC MIX — {len(WALLPAPERS)} wallpapers")
print("Category=PAISAJES (primary) + tags secundarios por mood")
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

print(f"\n[OK] Pack PANORAMIC mix {len(WALLPAPERS)} publicado")
