"""Pack PANORAMIC — paisajes 2026-07-04 (batch 1 de 10 imagenes).

10 paisajes generados con Grok 16:9 (1792x1008) — fantasia realista,
prehistorico y mitologia. Mismos IDs que los prompts que le pase a
Eduardo para trazabilidad.
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
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_paisages_batch1")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

SK = re.search(
    r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
).group(1)

WALLPAPERS = [
    {
        "id": "pano_bosque_carborifero",
        "src": "bosque_carborifero.jpg",
        "name": "Bosque Carbonifero",
        "description": "Selva del periodo Carbonifero hace 320 millones de anos: helechos gigantes, colas de caballo colosales y libelulas Meganeura de 70cm de envergadura entre rayos de luz en aire humedo rico en oxigeno.",
        "glow": "#65A30D",
        "tags": ["paisaje", "panoramica", "prehistorico", "carbonifero", "helechos", "libelulas", "bosque", "primigenio"],
    },
    {
        "id": "pano_bosque_encantado",
        "src": "bosque_encantado.jpg",
        "name": "Bosque Encantado Bioluminiscente",
        "description": "Bosque encantado al amanecer con arboles de savia turquesa fluorescente, esporas doradas flotando y rayos de luz refractandose en subtiles matices de arcoiris — atmosfera Weta Digital.",
        "glow": "#22D3EE",
        "tags": ["paisaje", "panoramica", "fantasia", "bosque", "bioluminiscente", "magico", "rayos", "prismatico"],
    },
    {
        "id": "pano_ciudad_flotante",
        "src": "ciudad_flotante.jpg",
        "name": "Ciudad Flotante en las Nubes",
        "description": "Ciudad vertical tallada en meseta suspendida sobre mar infinito de nubes al atardecer. Cascadas cayendo al vacio, spires de piedra unidos por puentes colgantes iluminados en oro fundido.",
        "glow": "#F59E0B",
        "tags": ["paisaje", "panoramica", "fantasia", "ciudad", "flotante", "nubes", "cascadas", "atardecer"],
    },
    {
        "id": "pano_escena_alpina_cristales",
        "src": "escena_alpina.jpg",
        "name": "Reino Cristalino Alpino",
        "description": "Formaciones cristalinas del tamano de catedrales brotando de la ladera alpina. Sol refracta en cuarzo generando arcoiris que se dispersan por la nieve — HDR de fantasia realista.",
        "glow": "#67E8F9",
        "tags": ["paisaje", "panoramica", "fantasia", "cristales", "alpes", "nieve", "arcoiris", "montanas"],
    },
    {
        "id": "pano_fiordo_artico_auroras",
        "src": "fiordo_artico.jpg",
        "name": "Fiordo con Auroras Boreales",
        "description": "Fiordo artico a medianoche con auroras boreales en verde esmeralda y violeta danzando sobre agua espejada. Silueta etearea de ballena cosmica emergiendo entre estrellas.",
        "glow": "#34D399",
        "tags": ["paisaje", "panoramica", "artico", "auroras", "fiordo", "ballena", "estrellas", "nordico"],
    },
    {
        "id": "pano_yggdrasil_arbol_cosmico",
        "src": "igdrasil_arbol_cosmico.jpg",
        "name": "Yggdrasil, Arbol del Mundo",
        "description": "Yggdrasil, el fresno cosmico de la mitologia nordica, se eleva colosal entre los nueve reinos. Raices sumergidas en vacio estrellado, ramas superiores tocando los cielos aurorales.",
        "glow": "#A78BFA",
        "tags": ["paisaje", "panoramica", "mitologia", "yggdrasil", "nordico", "cosmico", "arbol", "epico"],
    },
    {
        "id": "pano_mar_somero_devonico",
        "src": "mar_somero_deldebonico.jpg",
        "name": "Mar Devonico Somero",
        "description": "Mar Devonico hace 380 millones de anos: bosque primitivo de Wattieza sobre superficie y peces acorazados Dunkleosteus patrullando debajo. Rayos de sol en columnas doradas.",
        "glow": "#0EA5E9",
        "tags": ["paisaje", "panoramica", "prehistorico", "devonico", "mar", "peces", "acorazados", "submarino"],
    },
    {
        "id": "pano_oasis_subterraneo",
        "src": "oasis_subterraneo.jpg",
        "name": "Oasis Subterraneo con Cristales",
        "description": "Caverna gigante con oasis turquesa iluminado por unico rayo de sol penetrando la boveda. Columnas de selenita catedralicias, helechos colgantes y vapor mineral en el aire.",
        "glow": "#2DD4BF",
        "tags": ["paisaje", "panoramica", "cueva", "oasis", "cristales", "selenita", "subterraneo", "fantasia"],
    },
    {
        "id": "pano_pangea_volcan_activo",
        "src": "pangea_con_volcanactivo.jpg",
        "name": "Pangea con Volcan Activo",
        "description": "Paisaje del supercontinente Pangea en el Triasico: volcan escudo escupiendo lava roja hacia cielo cargado de ceniza. Palmeras primitivas y helechos primigenios en primer plano.",
        "glow": "#DC2626",
        "tags": ["paisaje", "panoramica", "prehistorico", "pangea", "volcan", "lava", "triasico", "primigenio"],
    },
    {
        "id": "pano_templo_perdido",
        "src": "templo_perdido.jpg",
        "name": "Templo Perdido en la Selva",
        "description": "Ruinas de templo devoradas por selva tropical. Rayos calidos rompen el dosel iluminando piscina secreta al centro. Guacamayas y mariposas capturan la luz — aventura Nat Geo.",
        "glow": "#84CC16",
        "tags": ["paisaje", "panoramica", "templo", "selva", "ruinas", "aventura", "misterio", "tropical"],
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
print(f"Pack PANORAMIC paisages batch 1 — {len(WALLPAPERS)} wallpapers")
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

print(f"\n[OK] paisages batch 1 ({len(WALLPAPERS)}) publicado")
