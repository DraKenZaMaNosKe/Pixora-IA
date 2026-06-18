"""
Pixora canvas_scene publisher — Pokemon Cafe 3D.

Source:
  · imagen_de_fondo_pokemon.png         → background (1080x1920 estatico)
  · chimenea_activa.gif (240x426, 60f)  → sprite chimenea (animado en posicion)
  · pokemon_gif_tomando_cafesito.gif    → sprite pikachu (animado en posicion)

Pipeline (mismo patron que Goku Genkidama):
  1. Extract 15 frames de cada GIF (downsample de 60+)
  2. ZIP cada set de frames
  3. Upload ZIPs a wallpaper-sprites/
  4. Update wallpaper-sprites/manifest.json (add 2 entries)
  5. Upload bg WebP a wallpaper-images/
  6. Create scene spec JSON con image_layer + 2 sprites
  7. Upload spec a wallpaper-scenes/pokemon_cafe_3d.json
  8. Bump catalog_index.json + add entry
  9. INSERT Postgres (type=static, category=SCENES — el cliente lo resuelve
     como canvas_scene via _resolveCanvasSceneFromPath buscando el basename)
  10. FCM invalidate wallpapers
"""
from __future__ import annotations
import io, json, re, sys, tempfile, urllib.request, zipfile
from datetime import datetime, timezone
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/pokemon")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_pokemon_3d")

SRC_BG     = SRC / "imagen_de_fondo_pokemon.png"
SRC_CHIM   = SRC / "chimenea_activa.gif"
SRC_PIKA   = SRC / "pokemon_gif_tomando_cafesito.gif"

OUT_BG_WEBP    = WORK / "pokemon_cafe_3d_bg.webp"
OUT_PREV_WEBP  = WORK / "pokemon_cafe_3d_preview.webp"
OUT_FLAT_WEBP  = WORK / "pokemon_cafe_3d.webp"  # fallback flat (igual al bg estatico)

# Sprite folders
CHIM_KEY = "pokemon_cafe/chimenea"
PIKA_KEY = "pokemon_cafe/pikachu"
CHIM_ZIP = WORK / "pokemon_cafe_chimenea.zip"
PIKA_ZIP = WORK / "pokemon_cafe_pikachu.zip"

# Storage paths
IMG_BUCKET     = "wallpaper-images"
SCENES_BUCKET  = "wallpaper-scenes"
SPRITES_BUCKET = "wallpaper-sprites"

R_BG       = "pokemon_cafe_3d_bg.webp"
R_PREVIEW  = "pokemon_cafe_3d_preview.webp"
R_FLAT     = "pokemon_cafe_3d.webp"
R_SPEC     = "pokemon_cafe_3d.json"
R_CATALOG  = "catalog_index.json"
R_MANIFEST = "manifest.json"

SCENE_ID  = "pokemon_cafe_3d"
STATIC_ID = "pokemon_cafe_3d_cozy"

TAGS = ["pokemon", "pikachu", "cafe", "chimenea", "casa", "cozy",
        "anime", "nintendo", "3d", "parallax", "animado"]
GLOW = "#FFCB05"  # Pikachu yellow

# How many frames to extract from each GIF (downsample from 60+ to keep
# ZIP size manageable and decode RAM low). 15 frames @ ~50KB each = ~750KB ZIP.
EXTRACT_FRAMES = 15
# Sprite positions on the background (normalized 0..1, centered anchor).
# Estimated from the static composite — adjust by editing spec JSON in
# Storage if visuals are off, no rebuild needed.
CHIM_POS = {"x": 0.36, "y": 0.50, "scale": 2.0}   # chimenea izquierda media
PIKA_POS = {"x": 0.55, "y": 0.65, "scale": 2.5}   # pikachu centro-derecha bajo
# frame_skip = how many render ticks per sprite frame advance. With ~30fps
# render and frame_skip=4, we get ~7fps sprite animation — natural for
# a slow fire + sipping motion. Lower = faster, higher = slower.
FRAME_SKIP_CHIM = 3   # fuego animado mas rapido
FRAME_SKIP_PIKA = 5   # bebida lenta natural


def load_service_key():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_service_key()


def put(bucket, remote, local, ct):
    body = local.read_bytes() if isinstance(local, Path) else local
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")
    return len(body)


def put_json(bucket, remote, data):
    payload = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=payload, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} (JSON)")


def get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


# ───────────────────── FASE 1: process ─────────────────────
def phase1_process():
    from PIL import Image
    print("\n[1/6] Procesamiento local")
    WORK.mkdir(parents=True, exist_ok=True)
    info = {}

    # 1a. Background WebP
    print("  · Background PNG -> WebP")
    bg = Image.open(SRC_BG).convert("RGB")
    info["bg_w"], info["bg_h"] = bg.width, bg.height
    bg.save(OUT_BG_WEBP, "WEBP", quality=90, method=6)
    info["bg_size"] = OUT_BG_WEBP.stat().st_size
    print(f"    {bg.width}x{bg.height}, {info['bg_size']:,} B")

    # 1b. Flat fallback (same image, used by clients that haven't activated
    # canvas_scene yet — and as the image_path in Postgres for grid preview)
    bg.save(OUT_FLAT_WEBP, "WEBP", quality=88, method=6)
    info["flat_size"] = OUT_FLAT_WEBP.stat().st_size

    # 1c. Preview thumbnail
    prev = bg.copy(); prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_PREV_WEBP, "WEBP", quality=85, method=6)
    info["prev_size"] = OUT_PREV_WEBP.stat().st_size
    print(f"  · Preview {prev.width}x{prev.height}, {info['prev_size']:,} B")

    # 1d/1e. Extract frames from GIFs + zip
    def extract_and_zip(src_gif: Path, out_zip: Path, label: str):
        gif = Image.open(src_gif)
        total = 0
        try:
            while True:
                gif.seek(total); total += 1
        except EOFError: pass
        # Sample EXTRACT_FRAMES evenly spaced
        indices = [int(i * total / EXTRACT_FRAMES) for i in range(EXTRACT_FRAMES)]
        print(f"  · {label} GIF: {total} frames -> sampling {len(indices)} ({src_gif.name})")
        # Build ZIP in memory then write
        buf = io.BytesIO()
        total_bytes = 0
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for out_i, src_i in enumerate(indices, start=1):
                gif.seek(src_i)
                frame = gif.convert("RGBA")
                fbuf = io.BytesIO()
                frame.save(fbuf, "PNG", optimize=True)
                data = fbuf.getvalue()
                name = f"frame_{out_i:03d}.png"
                zf.writestr(name, data)
                total_bytes += len(data)
        out_zip.write_bytes(buf.getvalue())
        size_zip = out_zip.stat().st_size
        print(f"    -> {out_zip.name}: {len(indices)} frames, raw={total_bytes:,} B, zip={size_zip:,} B")
        return {"frames": len(indices), "raw_size": total_bytes, "zip_size": size_zip}

    info["chim"] = extract_and_zip(SRC_CHIM, CHIM_ZIP, "Chimenea")
    info["pika"] = extract_and_zip(SRC_PIKA, PIKA_ZIP, "Pikachu")
    return info


# ───────────────────── FASE 2: upload assets ─────────────────────
def phase2_upload(info):
    print("\n[2/6] Upload assets (bg + flat + preview + 2 sprite ZIPs)")
    put(IMG_BUCKET, R_BG, OUT_BG_WEBP, "image/webp")
    put(IMG_BUCKET, R_FLAT, OUT_FLAT_WEBP, "image/webp")
    put(IMG_BUCKET, R_PREVIEW, OUT_PREV_WEBP, "image/webp")
    put(SPRITES_BUCKET, "pokemon_cafe_chimenea.zip", CHIM_ZIP, "application/zip")
    put(SPRITES_BUCKET, "pokemon_cafe_pikachu.zip",  PIKA_ZIP, "application/zip")


# ───────────────────── FASE 3: sprite manifest ─────────────────────
def phase3_manifest(info):
    print("\n[3/6] Update wallpaper-sprites/manifest.json")
    manifest = get_json(SPRITES_BUCKET, R_MANIFEST)
    # Use the SAME shape as goku_genkidama_orb (simple: zip + frames + size)
    # — sprite_download_service.dart reads info['zip'] and info['frames'] only.
    manifest[CHIM_KEY] = {
        "zip": "pokemon_cafe_chimenea.zip",
        "frames": info["chim"]["frames"],
        "size": info["chim"]["zip_size"],
    }
    manifest[PIKA_KEY] = {
        "zip": "pokemon_cafe_pikachu.zip",
        "frames": info["pika"]["frames"],
        "size": info["pika"]["zip_size"],
    }
    print(f"  · manifest now has {len(manifest)} entries (+2 nuevas)")
    put_json(SPRITES_BUCKET, R_MANIFEST, manifest)


# ───────────────────── FASE 4: scene spec ─────────────────────
def phase4_spec(info):
    print("\n[4/6] Create + upload scene spec")
    url_bg   = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_BG}"
    url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_FLAT}"
    url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}"

    spec = {
        "schema_version": 1,
        "id": SCENE_ID,
        "type": "canvas_scene",
        "title": {
            "en": "Pokemon Cafe 3D",
            "es": "Pokemon Cafe 3D",
        },
        "tags": TAGS,
        "category": "anime",
        "featured": True,
        "background": {
            "url": url_flat,
            "preview_url": url_prev,
            "scroll": False,
        },
        # Background como image_layer z=0 sin parallax (queda fijo).
        # Sin bob — la animacion de los sprites ya da vida a la escena.
        "image_layers": [
            {
                "key": "bg",
                "url": url_bg,
                "parallax_factor": 0.0,
                "scroll_factor": 0.0,
                "z": 0,
                "scale": 1.0,
            },
        ],
        # 2 sprites en posicion fija con loop infinito de frames.
        # behavior=static = sin movimiento procedural (parallax_factor=0
        # opcional aqui, ya que el sprite no se mueve por tilt). frame_skip
        # controla velocidad del loop.
        "sprites": [
            {
                "name": "chimenea",
                "manifest_key": CHIM_KEY,
                "behavior": "static",
                "frame_skip": FRAME_SKIP_CHIM,
                "params": {
                    "x": CHIM_POS["x"],
                    "y": CHIM_POS["y"],
                    "scale": CHIM_POS["scale"],
                    "alpha": 255,
                    "parallax_factor": 0.0,
                },
            },
            {
                "name": "pikachu",
                "manifest_key": PIKA_KEY,
                "behavior": "static",
                "frame_skip": FRAME_SKIP_PIKA,
                "params": {
                    "x": PIKA_POS["x"],
                    "y": PIKA_POS["y"],
                    "scale": PIKA_POS["scale"],
                    "alpha": 255,
                    "parallax_factor": 0.0,
                },
            },
        ],
        "particles": [],
        "events": [],
    }

    # Validate vocab
    KNOWN_BEHAVIORS = {'orbit','wander','translate','static','preload'}
    for sp in spec['sprites']:
        assert sp['behavior'] in KNOWN_BEHAVIORS, f"behavior {sp['behavior']} fuera de vocab"
    print(f"  · spec validado (2 sprites + 1 image_layer)")
    put_json(SCENES_BUCKET, R_SPEC, spec)
    return spec


# ───────────────────── FASE 5: catalog_index + Postgres ─────────────────────
def phase5_catalog_and_postgres(info, spec):
    print("\n[5/6] catalog_index.json + Postgres INSERT")

    # 5a. catalog_index.json upsert
    cat = get_json(IMG_BUCKET, R_CATALOG)
    cat["version"] = (cat.get("version", 0) or 0) + 1
    entry = {
        "id": SCENE_ID,
        "type": "canvas_scene",
        "schema": 1,
        "title": spec["title"],
        "preview_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}",
        "tags": TAGS,
        "category": "anime",
        "featured": True,
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{R_SPEC}",
    }
    items = cat.get("items", [])
    idx = next((i for i, it in enumerate(items) if it.get("id") == SCENE_ID), -1)
    if idx >= 0:
        items[idx] = entry
        print(f"  · catalog_index: {SCENE_ID} replace")
    else:
        items.append(entry)
        print(f"  · catalog_index: {SCENE_ID} append (total {len(items)})")
    cat["items"] = items
    put_json(IMG_BUCKET, R_CATALOG, cat)
    print(f"  · catalog version bumped to {cat['version']}")

    # 5b. Postgres INSERT — type=static, category=SCENES (cliente lo resuelve
    # como canvas_scene via _resolveCanvasSceneFromPath buscando el basename
    # del image_path en catalog_index).
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    print(f"  · sort_order: {next_sort}")
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'SCENES'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, true, 0,
            true, false, %s, %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description, tags=EXCLUDED.tags,
            image_path=EXCLUDED.image_path, preview_path=EXCLUDED.preview_path,
            image_size=EXCLUDED.image_size, preview_size=EXCLUDED.preview_size,
            glow_color=EXCLUDED.glow_color, badge=EXCLUDED.badge,
            featured=EXCLUDED.featured, published=EXCLUDED.published,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            updated_at=now()
        RETURNING id;
    """, (
        STATIC_ID, "Pokemon Cafe 3D",
        "Pikachu tomando cafecito junto a la chimenea con efecto 3D — sprites animados con loop",
        TAGS, R_FLAT, R_PREVIEW, info["flat_size"], info["prev_size"], GLOW,
        next_sort, "Pixora Studio", info["bg_w"], info["bg_h"]
    ))
    print(f"  · postgres upserted: {cur.fetchone()[0]}")
    conn.commit(); cur.close(); conn.close()


# ───────────────────── FASE 6: FCM ─────────────────────
def phase6_fcm():
    print("\n[6/6] FCM invalidate")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  · wallpapers -> {send_catalog_invalidate('wallpapers')}")


if __name__ == "__main__":
    print("=" * 60)
    print("Pokemon Cafe 3D — canvas_scene publisher (sprites animados)")
    print("=" * 60)
    for src in (SRC_BG, SRC_CHIM, SRC_PIKA):
        if not src.exists(): raise SystemExit(f"No existe {src}")
    info = phase1_process()
    phase2_upload(info)
    phase3_manifest(info)
    spec = phase4_spec(info)
    phase5_catalog_and_postgres(info, spec)
    phase6_fcm()
    print("\n" + "=" * 60)
    print(f"Pokemon Cafe 3D publicado")
    print(f"  · bg: {info['bg_w']}x{info['bg_h']}")
    print(f"  · chimenea: {info['chim']['frames']} frames, zip {info['chim']['zip_size']:,} B")
    print(f"  · pikachu : {info['pika']['frames']} frames, zip {info['pika']['zip_size']:,} B")
    print(f"  · spec: wallpaper-scenes/{R_SPEC}")
    print("=" * 60)
    print("\nSi posiciones quedan mal, edita CHIM_POS / PIKA_POS arriba y re-run")
    print("o edita directo el spec JSON en Storage (sin rebuild de app).")
