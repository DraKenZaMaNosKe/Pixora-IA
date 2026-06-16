"""
Pixora canvas_scene publisher — Throotle 3D Underwater (parallax + particles).

Eduardo me paso layers separados:
  · throtle_fondo_soloelfondo.png  → fondo (sin tortuga)
  · throtle_solo_latortuga.png     → tortuga con transparency
  · throtle_escalagris.png         → depth map (no usado por sistema actual)

Sistema: el renderer Kotlin (scene/CanvasSceneRenderer.kt + SceneSpec.kt)
soporta image_layers con parallaxFactor (gyro tilt) + scrollFactor + z-order.
NINGUN spec publicado en wallpaper-scenes/ usa esto aun — Throotle es
el primero. Sistema validado, vocabulario en orden.

Flujo:
  1. Procesar PNG → WebP optimizado (background + sprite turtle + preview)
  2. Upload a Storage:
       wallpaper-images/throotle_3d_bg.webp       (background layer)
       wallpaper-images/throotle_3d_turtle.webp   (foreground layer w/ alpha)
       wallpaper-images/throotle_3d_preview.webp  (catalog thumbnail)
       wallpaper-images/throotle_3d.webp          (fallback flat — para clientes
                                                   sin canvas_scene activado)
  3. Crear spec JSON con image_layers + bubbles + motes
  4. Upload spec a wallpaper-scenes/throotle_3d.json
  5. Actualizar catalog_index.json (version bump + add entry)
  6. INSERT en Postgres wallpapers (type=static, category=SCENES)
  7. FCM invalidate
"""
from __future__ import annotations
import sys, re, json, urllib.request, time, io
from datetime import datetime, timezone
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/throotle")
WORK_DIR = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_throotle3d")

SRC_BG = SRC_DIR / "throtle_fondo_soloelfondo.png"
SRC_TURTLE = SRC_DIR / "throtle_solo_latortuga.png"
SRC_FLAT = SRC_DIR / "throttle_underwater_completa.png"

OUT_BG = WORK_DIR / "throotle_3d_bg.webp"
OUT_TURTLE = WORK_DIR / "throotle_3d_turtle.webp"
OUT_FLAT = WORK_DIR / "throotle_3d.webp"
OUT_PREVIEW = WORK_DIR / "throotle_3d_preview.webp"

IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"

R_BG = "throotle_3d_bg.webp"
R_TURTLE = "throotle_3d_turtle.webp"
R_FLAT = "throotle_3d.webp"
R_PREVIEW = "throotle_3d_preview.webp"
R_SPEC = "throotle_3d.json"
R_CATALOG = "catalog_index.json"

SCENE_ID = "throotle_3d"
STATIC_ID = "throotle_3d_underwater"

TAGS_EN = ["pokemon", "throotle", "turtle", "underwater", "ocean", "anime", "live", "animated", "parallax", "3d"]
TAGS_ES = ["pokemon", "throotle", "tortuga", "agua", "oceano", "anime", "vivo", "animado", "parallax", "3d"]


def load_service_key():
    keys = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", keys).group(1)


SERVICE_KEY = load_service_key()


def storage_put(bucket, remote, local, content_type):
    body = local.read_bytes()
    url = f"{PROJECT}/storage/v1/object/{bucket}/{remote}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", content_type)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote}  -> {r.status} ({len(body):,} bytes)")
    return len(body)


def storage_put_json(bucket, remote, data):
    payload = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    url = f"{PROJECT}/storage/v1/object/{bucket}/{remote}"
    req = urllib.request.Request(url, data=payload, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote}  -> {r.status} (JSON)")


def storage_get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


# ───────────────────── FASE 1: procesar layers ─────────────────────
def phase1_process():
    from PIL import Image
    print("\n[1/6] Procesar layers WebP")
    WORK_DIR.mkdir(parents=True, exist_ok=True)

    info = {}

    print("  · Background (fondo sin tortuga)")
    bg = Image.open(SRC_BG).convert("RGB")  # background no necesita alpha
    info["bg_w"], info["bg_h"] = bg.width, bg.height
    bg.save(OUT_BG, "WEBP", quality=88, method=6)
    info["bg_size"] = OUT_BG.stat().st_size
    print(f"    {bg.width}x{bg.height}, {info['bg_size']:,} bytes")

    print("  · Turtle (foreground con alpha)")
    turtle = Image.open(SRC_TURTLE).convert("RGBA")
    info["turtle_w"], info["turtle_h"] = turtle.width, turtle.height
    turtle.save(OUT_TURTLE, "WEBP", quality=90, method=6, lossless=False)
    info["turtle_size"] = OUT_TURTLE.stat().st_size
    print(f"    {turtle.width}x{turtle.height} RGBA, {info['turtle_size']:,} bytes")

    print("  · Fallback flat (imagen completa)")
    flat = Image.open(SRC_FLAT).convert("RGB")
    info["flat_w"], info["flat_h"] = flat.width, flat.height
    flat.save(OUT_FLAT, "WEBP", quality=90, method=6)
    info["flat_size"] = OUT_FLAT.stat().st_size
    print(f"    {flat.width}x{flat.height}, {info['flat_size']:,} bytes")

    print("  · Preview thumbnail")
    prev = flat.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_PREVIEW, "WEBP", quality=85, method=6)
    info["prev_size"] = OUT_PREVIEW.stat().st_size
    print(f"    {prev.width}x{prev.height}, {info['prev_size']:,} bytes")

    return info


# ───────────────────── FASE 2: upload Storage ─────────────────────
def phase2_upload(info):
    print("\n[2/6] Upload assets a Storage")
    storage_put(IMG_BUCKET, R_BG, OUT_BG, "image/webp")
    storage_put(IMG_BUCKET, R_TURTLE, OUT_TURTLE, "image/webp")
    storage_put(IMG_BUCKET, R_FLAT, OUT_FLAT, "image/webp")
    storage_put(IMG_BUCKET, R_PREVIEW, OUT_PREVIEW, "image/webp")


# ───────────────────── FASE 3: crear y subir spec ─────────────────────
def phase3_spec(info):
    print("\n[3/6] Crear scene spec JSON")

    url_bg = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_BG}"
    url_turtle = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_TURTLE}"
    url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_FLAT}"
    url_preview = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}"

    spec = {
        "schema_version": 1,
        "id": SCENE_ID,
        "type": "canvas_scene",
        "title": {
            "en": "Throotle Underwater 3D",
            "es": "Throotle Bajo el Agua 3D",
        },
        "tags": TAGS_EN,
        "category": "anime",
        "featured": True,

        # Background fallback — usado si image_layers no se renderea (cliente
        # viejo que no soporta image_layers todavia, aunque el sistema actual
        # ya lo soporta).
        "background": {
            "url": url_flat,
            "preview_url": url_preview,
            "scroll": False,
        },

        # 3D parallax layers (PRIMER spec en usar esto en produccion).
        # parallax_factor: tilt con gyroscope (0=static, 1=full tilt).
        # scroll_factor: pan horizontal con home swipe (0=fixed, 1=panoramic).
        # z: order, mayor = mas adelante.
        "image_layers": [
            {
                "key": "bg",
                "url": url_bg,
                "parallax_factor": 0.05,  # fondo casi estatico, sutil profundidad
                "scroll_factor": 0.0,     # no pan con home swipe
                "z": 0,
                "scale": 1.0,
            },
            {
                "key": "turtle",
                "url": url_turtle,
                "parallax_factor": 0.45,  # tortuga adelante, bastante gyro tilt
                "scroll_factor": 0.0,
                "z": 1,
                "scale": 1.0,
            },
        ],

        # Sin sprites — la tortuga es un image_layer estatico que se mueve
        # solo con el gyroscope (parallax). Para flotacion procedural en el
        # futuro habria que extender CapabilityRegistry.knownSpriteBehaviors
        # con 'float'.
        "sprites": [],

        # Particles atmosfericos submarinos.
        "particles": [
            {
                "kind": "bubbles",
                "params": {
                    "count": 28,
                    "size_min_px": 4,
                    "size_max_px": 11,
                    "color": "#FFCFE9FF",       # cyan tenue
                    "max_alpha": 180,
                    "vy_min": -0.45,            # ascendiendo
                    "vy_max": -0.18,
                    "spawn_top": 0.7,           # nacen en mitad inferior
                    "spawn_bottom": 1.0,
                },
            },
            {
                "kind": "motes",
                "params": {
                    "count": 36,
                    "drift": 0.5,
                    "vy_min": -0.25,
                    "vy_max": 0.15,             # algunos suben, otros bajan
                    "color": "#FFF8FBFF",       # blanco muy tenue
                    "max_alpha": 140,
                },
            },
        ],
    }

    print(f"  · spec_version={spec['schema_version']}, layers={len(spec['image_layers'])}, "
          f"particles={len(spec['particles'])}")

    # Validar localmente: behaviors + particles dentro del vocab supported
    KNOWN_PARTICLES = {'embers','motes','bubbles','snow','rain','wisps',
                       'glass_drops','fireflies','oncoming_lights','perspective_posts'}
    for p in spec['particles']:
        assert p['kind'] in KNOWN_PARTICLES, f"particle {p['kind']} fuera de vocab"
    KNOWN_BEHAVIORS = {'orbit','wander','translate','static','preload'}
    for sp in spec['sprites']:
        assert sp['behavior'] in KNOWN_BEHAVIORS, f"sprite behavior {sp['behavior']} fuera de vocab"
    print("  · vocab OK")

    storage_put_json(SCENES_BUCKET, R_SPEC, spec)
    return spec


# ───────────────────── FASE 4: catalog_index update ─────────────────────
def phase4_catalog(info, spec):
    print("\n[4/6] Update catalog_index.json")

    cat = storage_get_json(IMG_BUCKET, R_CATALOG)
    cat['version'] = (cat.get('version', 0) or 0) + 1

    entry = {
        "id": SCENE_ID,
        "type": "canvas_scene",
        "schema": 1,
        "title": spec['title'],
        "preview_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}",
        "tags": TAGS_EN,
        "category": "anime",
        "featured": True,
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{R_SPEC}",
    }

    # Upsert por id
    items = cat.get('items', [])
    idx = next((i for i, it in enumerate(items) if it.get('id') == SCENE_ID), -1)
    if idx >= 0:
        print(f"  · {SCENE_ID} en catalog_index → replace")
        items[idx] = entry
    else:
        print(f"  · {SCENE_ID} append (catalog now has {len(items)+1} items)")
        items.append(entry)
    cat['items'] = items

    storage_put_json(IMG_BUCKET, R_CATALOG, cat)
    print(f"  · version bumped to {cat['version']}")


# ───────────────────── FASE 5: INSERT Postgres ─────────────────────
def phase5_postgres(info):
    print("\n[5/6] INSERT Postgres wallpapers (static, SCENES)")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect

    conn = None
    for attempt in range(3):
        try:
            conn = connect(); break
        except Exception as e:
            print(f"  retry {attempt+1}/3: {str(e)[:80]}")
            time.sleep(3)
    if conn is None:
        print("  ⚠️  Postgres unreachable — INSERT skipped, hacer manual despues")
        return

    cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    print(f"  next sort_order: {next_sort}")

    # type=static, category=SCENES — el cliente lo resuelve como canvas_scene
    # vía _resolveCanvasSceneFromPath(basename) → busca en catalog_index.json
    # el id que matchee y carga el spec si type=canvas_scene.
    # image_path apunta al flat WebP para que el grid/holocard muestren preview.
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'SCENES'::wallpaper_category, %s,
            %s, %s, %s, %s,
            %s, 'NEW'::wallpaper_badge, %s, true, 0,
            true, false, %s, %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            description = EXCLUDED.description,
            tags = EXCLUDED.tags,
            image_path = EXCLUDED.image_path,
            preview_path = EXCLUDED.preview_path,
            image_size = EXCLUDED.image_size,
            preview_size = EXCLUDED.preview_size,
            glow_color = EXCLUDED.glow_color,
            badge = EXCLUDED.badge,
            featured = EXCLUDED.featured,
            published = EXCLUDED.published,
            updated_at = now()
        RETURNING id;
    """, (
        STATIC_ID,
        "Throotle 3D",
        "Throotle Pokemon bajo el mar con efecto parallax 3D · "
        "fondo + tortuga separados con tilt giroscopio + burbujas + particulas",
        TAGS_ES,
        R_FLAT,              # image_path = flat fallback (cliente sin canvas_scene)
        R_PREVIEW,
        info["flat_size"],
        info["prev_size"],
        "#5BC7FF",
        next_sort,
        "Pixora Studio",
        info["flat_w"],
        info["flat_h"],
    ))
    print(f"  upserted: {cur.fetchone()[0]}")
    conn.commit(); cur.close(); conn.close()


# ───────────────────── FASE 6: FCM ─────────────────────
def phase6_fcm():
    print("\n[6/6] FCM invalidate wallpapers")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")


if __name__ == "__main__":
    print("=" * 60)
    print("Throotle 3D — canvas_scene parallax publisher")
    print("=" * 60)
    for f in (SRC_BG, SRC_TURTLE, SRC_FLAT):
        if not f.exists(): raise SystemExit(f"No existe {f}")

    info = phase1_process()
    phase2_upload(info)
    spec = phase3_spec(info)
    phase4_catalog(info, spec)
    phase5_postgres(info)
    phase6_fcm()

    print("\n" + "=" * 60)
    print("✅ Throotle 3D publicado")
    print("=" * 60)
    print(f"  · scene_id: {SCENE_ID}")
    print(f"  · wallpaper_id: {STATIC_ID}")
    print(f"  · 2 image_layers (bg parallax=0.05, turtle parallax=0.45)")
    print(f"  · 2 particles (bubbles + motes)")
    print(f"  · category: SCENES (sección 3D de la app)")
    print(f"  · PRIMER spec en producción usando image_layers con gyro parallax")
    print(f"\nPara probarlo: open Pixora → sección 3D/Scenes → Throotle 3D → APPLY")
