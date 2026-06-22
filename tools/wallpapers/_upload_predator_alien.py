"""
Pixora · Batch publisher — Depredador vs Alien Vol. I

Sube 5 panorámicas generadas con Grok (aspect 1.78:1) — Yautja vs
Xenomorph en escenarios de selva, con el cazador siempre en ventaja.

  1. Visión térmica (HUD del casco)
  2. Cazador en altura (Yautja en copas)
  3. Camuflaje activo (silueta + cascada)
  4. Lluvia y trofeos (cresta bajo tormenta)
  5. POV del cazador (mira del cañón de hombro)

NOTA IP: Predator (Yautja) y Alien (Xenomorph) son IP registradas de
20th Century Studios / Disney. Eduardo aceptó el riesgo conscientemente
(2026-06-21) — si llega DMCA takedown, las bajamos rápido vía
_replace_asset.py o UPDATE wallpapers SET published=false.
"""
from __future__ import annotations
import re, sys, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/predator_alien")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_predator")

COMMON_TAGS = ["predator", "alien", "depredador", "xenomorph", "yautja",
               "selva", "scifi", "cazador", "panoramico"]

WALLPAPERS = [
    {
        "id": "pano_predator_vision_termica",
        "src": "predator_01_vision_termica.jpg",
        "name": "Depredador · Visión Térmica",
        "description": "Selva nocturna en mapa de calor — el xenomorph brilla como firma caliente, el entorno frío en azul y violeta. Sensación de HUD desde el casco del Yautja.",
        "glow": "#7B2CFF",
        "extra_tags": ["vision_termica", "hud", "noche"],
    },
    {
        "id": "pano_predator_cazador_altura",
        "src": "predator_02_cazador_altura.jpg",
        "name": "Depredador · Cazador en Altura",
        "description": "Yautja entre las copas con el plasma blaster apuntando — el alien cruza el sotobosque sin notar al depredador encima.",
        "glow": "#FF3030",
        "extra_tags": ["altura", "blaster", "copas"],
    },
    {
        "id": "pano_predator_camuflaje_activo",
        "src": "predator_03_camuflaje_activo.jpg",
        "name": "Depredador · Camuflaje Activo",
        "description": "Silueta casi invisible junto a la cascada — restos de huevo de xenomorph y hojas quemadas por ácido. El alien está en sombra, observado sin saberlo.",
        "glow": "#4FD1C5",
        "extra_tags": ["camuflaje", "sigilo", "cascada"],
    },
    {
        "id": "pano_predator_lluvia_trofeos",
        "src": "predator_04_lluvia_trofeos.jpg",
        "name": "Depredador · Lluvia y Trofeos",
        "description": "Cazador en la cresta bajo tormenta tropical — el xenomorph se retira herido al matorral. Trofeos colgando del cinto, lluvia chocando contra la armadura.",
        "glow": "#5C7080",
        "extra_tags": ["lluvia", "tormenta", "trofeos"],
    },
    {
        "id": "pano_predator_pov_cazador",
        "src": "predator_05_pov_cazador.jpg",
        "name": "Depredador · POV del Cazador",
        "description": "Vista por la mira del cañón de hombro — punto láser fijo sobre el alien desprevenido. HUD triangular y diagnósticos del casco a los costados.",
        "glow": "#FF1744",
        "extra_tags": ["pov", "mira", "laser", "hud"],
    },
]

AUTHOR = "Pixora Studio"


def load_sk():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_sk()


def put(remote, body, ct):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/wallpaper-images/{remote}",
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
    print("Depredador vs Alien Vol. I — batch publisher (5 panorámicas)")
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

        put(full_remote, full_bytes, "image/webp")
        put(prev_remote, prev_bytes, "image/webp")

        cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
        next_sort = cur.fetchone()[0]
        all_tags = COMMON_TAGS + w["extra_tags"]
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
            w["id"], w["name"], w["description"], all_tags,
            full_remote, prev_remote,
            len(full_bytes), len(prev_bytes),
            w["glow"], next_sort, AUTHOR,
            img.width, img.height,
        ))
        rid, rsort = cur.fetchone()
        print(f"    postgres: {rid}  sort_order={rsort}")
    conn.commit(); cur.close(); conn.close()

    print("\n[FCM] invalidate topic wallpapers")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"    -> {send_catalog_invalidate('wallpapers')}")

    print("\n" + "=" * 70)
    print(f"Publicados {len(WALLPAPERS)} Depredador vs Alien")
    print("=" * 70)


if __name__ == "__main__":
    main()
