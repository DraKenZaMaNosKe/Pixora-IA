"""Batch upload — 11 wallpapers nuevos (mezcla portrait + pano)."""
import re, sys, shutil, urllib.request
from pathlib import Path
from PIL import Image
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
DOWNLOADS = Path(r"C:/Users/lalo/Downloads")
BACKUP = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/2026_06_21_mix")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_mix")
BACKUP.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)
SK = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
               Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")).group(1)

ITEMS = [
    {"uuid": "86ea4a2d", "new": "calle_neon_carmesi", "id": "pano_calle_neon_carmesi",
     "name": "Calle Neón · Carmesí",
     "description": "Calle de ciudad nocturna inundada en luces de neón rojas, vapor saliendo de las rejillas, vibe cyberpunk urbano.",
     "kind": "panoramic", "cat": "PANORAMIC", "glow": "#E11D48",
     "tags": ["neon", "ciudad", "cyberpunk", "noche", "rojo", "urbano", "panoramico"]},
    {"uuid": "7462f6fd", "new": "convoy_estelar", "id": "pano_convoy_estelar",
     "name": "Convoy Estelar",
     "description": "Pequenos animales viajando en el cielo nocturno entre estrellas y constelaciones — magia infantil cosmica.",
     "kind": "panoramic", "cat": "PANORAMIC", "glow": "#60A5FA",
     "tags": ["animales", "espacio", "cosmos", "magico", "infantil", "estrellas", "panoramico"]},
    {"uuid": "1b1a1b55", "new": "travesia_violeta", "id": "pano_travesia_violeta",
     "name": "Travesía Violeta",
     "description": "Cohete cruzando un cielo violeta profundo lleno de estrellas y nebulosas — viaje epico interestelar.",
     "kind": "panoramic", "cat": "PANORAMIC", "glow": "#A855F7",
     "tags": ["cohete", "violeta", "espacio", "viaje", "cosmos", "nebulosa", "panoramico"]},
    {"uuid": "f6d0c7ac", "new": "ventana_atardecer", "id": "pano_ventana_atardecer",
     "name": "Ventana al Atardecer",
     "description": "Vista interior con figura asomada a una ventana grande, atardecer dorado sobre la ciudad — momento de pausa contemplativa.",
     "kind": "panoramic", "cat": "PANORAMIC", "glow": "#F97316",
     "tags": ["ventana", "atardecer", "contemplacion", "ciudad", "dorado", "panoramico"]},
    {"uuid": "f990bd17", "new": "bosque_aurora", "id": "pano_bosque_aurora",
     "name": "Bosque de la Aurora",
     "description": "Paisaje boscoso bajo una aurora boreal verde-violeta intensa, lagos espejo y montanas distantes.",
     "kind": "panoramic", "cat": "PANORAMIC", "glow": "#A3E635",
     "tags": ["bosque", "aurora", "boreal", "naturaleza", "noche", "verde", "panoramico"]},
    {"uuid": "daafcd05", "new": "siluetas_anochecer", "id": "pano_siluetas_anochecer",
     "name": "Siluetas al Anochecer",
     "description": "Figuras humanas en silueta contra un atardecer dramatico, fogata pequena al frente y desierto rojizo.",
     "kind": "panoramic", "cat": "PANORAMIC", "glow": "#FB7185",
     "tags": ["siluetas", "atardecer", "fogata", "desierto", "rojo", "viaje", "panoramico"]},
    {"uuid": "86e72af5", "new": "torre_calabazas", "id": "torre_calabazas",
     "name": "Torre de las Calabazas",
     "description": "Edificio alto con ventanas iluminadas en ambar y calabazas decorando cada piso — vibe Halloween calido.",
     "kind": "static", "cat": "NATURE", "glow": "#F59E0B",
     "tags": ["torre", "calabazas", "halloween", "ambar", "noche", "edificio"]},
    {"uuid": "75d6ab92", "new": "mascotas_cielo", "id": "mascotas_cielo",
     "name": "Mascotas del Cielo",
     "description": "Animalitos voladores en un cielo dorado con globos y nubes pintadas — fantasia juvenil magica.",
     "kind": "static", "cat": "NATURE", "glow": "#FACC15",
     "tags": ["mascotas", "animales", "cielo", "dorado", "magico", "fantasy"]},
    {"uuid": "eaa7615f", "new": "cometa_cosmico", "id": "cometa_cosmico",
     "name": "Cometa Cósmico",
     "description": "Cometa atravesando un cielo nocturno estrellado, dejando estela brillante en violeta y dorado.",
     "kind": "static", "cat": "NATURE", "glow": "#7C3AED",
     "tags": ["cometa", "cosmos", "noche", "estrellas", "violeta", "espacio"]},
    {"uuid": "03ac4fa8", "new": "mirada_turquesa", "id": "mirada_turquesa",
     "name": "Mirada Turquesa",
     "description": "Retrato de joven con cabello turquesa y mirada serena, paleta cyan-violeta — estilo anime ilustrado.",
     "kind": "static", "cat": "ANIME", "glow": "#22D3EE",
     "tags": ["retrato", "anime", "turquesa", "ilustracion", "cabello_azul", "chica"]},
    {"uuid": "77b45013", "new": "torre_violeta", "id": "torre_violeta",
     "name": "Torre Violeta",
     "description": "Torre solitaria contra un cielo violeta dramatico con nubes tormentosas y rayos lejanos.",
     "kind": "static", "cat": "NATURE", "glow": "#9333EA",
     "tags": ["torre", "violeta", "tormenta", "dramatico", "cielo", "fantasy"]},
]


def put(remote, body):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/wallpaper-images/{remote}",
        data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", "image/webp")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"    PUT {remote} -> {r.status} ({len(body):,} B)")


def main():
    conn = connect(); cur = conn.cursor()
    for w in ITEMS:
        matches = list(DOWNLOADS.glob(f"*{w['uuid']}*.jpg"))
        if not matches:
            print(f"\n[SKIP] {w['id']}: no encontrado *{w['uuid']}*"); continue
        src = matches[0]
        print(f"\n[{w['id']}]  {w['name']}")
        new_dl = DOWNLOADS / f"{w['new']}.jpg"
        if src != new_dl:
            src.rename(new_dl); src = new_dl
        shutil.copy2(src, BACKUP / f"{w['new']}.jpg")
        img = Image.open(src).convert("RGB")
        print(f"    source {img.width}x{img.height}  ({w['kind']})")
        full_remote = f"{w['id']}.webp"
        prev_remote = f"{w['id']}_preview.webp"
        full_path = WORK / full_remote
        img.save(full_path, "WEBP", quality=90, method=6)
        full_bytes = full_path.read_bytes()
        prev = img.copy()
        max_side = 1080 if w["kind"] == "panoramic" else 540
        prev.thumbnail((max_side, max_side * 2), Image.LANCZOS)
        prev_path = WORK / prev_remote
        prev.save(prev_path, "WEBP",
                  quality=82 if w["kind"] == "panoramic" else 85, method=6)
        prev_bytes = prev_path.read_bytes()
        put(full_remote, full_bytes)
        put(prev_remote, prev_bytes)
        cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
        sort = cur.fetchone()[0]
        cur.execute(f"""
            INSERT INTO wallpapers (
                id, name, description, type, category, tags,
                image_path, preview_path, image_size, preview_size,
                glow_color, badge, sort_order, featured, trending_score,
                published, daily_eligible, author_name,
                media_width, media_height
            ) VALUES (
                %s, %s, %s, '{w["kind"]}'::wallpaper_type,
                '{w["cat"]}'::wallpaper_category, %s,
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
                updated_at=now()
            RETURNING id, sort_order;
        """, (w["id"], w["name"], w["description"], w["tags"],
              full_remote, prev_remote, len(full_bytes), len(prev_bytes),
              w["glow"], sort, img.width, img.height))
        rid, rsort = cur.fetchone()
        print(f"    postgres: {rid}  sort={rsort}")
    conn.commit(); cur.close(); conn.close()
    print("\n[FCM] invalidate wallpapers")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  -> {send_catalog_invalidate('wallpapers')}")
    print(f"\n[OK] Batch completo")


if __name__ == "__main__":
    main()
