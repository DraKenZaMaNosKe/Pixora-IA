"""
Pixora canvas_scene publisher — Alicia en el País de las Maravillas.

Source (C:/Users/lalo/Desktop/wallPapers_repo/nuevos/alicia_wonderland):
  · alicia_solofondo.png                      → background (bosque + cola, opaco)
  · alicia_wonderland_wallpaper_estatico.png  → flat fallback + preview (composición completa)
  · alicia_solo_alicia.png                    → sprite Alicia (PNG transparente, 1 frame)
  · alicia_soloelgatito.png                   → sprite Gato de Cheshire (PNG transparente, 1 frame)

Los sprites son ESTÁTICOS (1 frame cada uno) — no GIFs. El ZIP lleva un solo
frame_001.png. En el sprite editor el usuario posiciona/da parallax:
  · Gato = fijo (parallax 0), su cola coincide con la del fondo (efecto buscado)
  · Alicia = se mueve con el tilt (parallax leve)

Los defaults (x=0.5, y=0.5, scale=1.0) reconstruyen la composición original,
así que se ve bien desde el arranque y el usuario solo afina en el editor.

NO dispara FCM: la escena queda publicada pero el cache de los clientes se
refresca cuando el usuario termine de editar en el sprite editor y guarde
(ese POST /api/save-scene-sprites dispara el FCM). Así no se notifica con
posiciones a medias.
"""
from __future__ import annotations
import io, json, re, sys, urllib.request, zipfile
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC  = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/alicia_wonderland")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_alicia")

SRC_BG     = SRC / "alicia_solofondo.png"
SRC_FLAT   = SRC / "alicia_wonderland_wallpaper_estatico.png"
SRC_ALICIA = SRC / "alicia_solo_alicia.png"
SRC_GATO   = SRC / "alicia_soloelgatito.png"

OUT_BG_WEBP   = WORK / "alicia_wonderland_bg.webp"
OUT_FLAT_WEBP = WORK / "alicia_wonderland.webp"
OUT_PREV_WEBP = WORK / "alicia_wonderland_preview.webp"
ALICIA_ZIP    = WORK / "alicia_wonderland_alicia.zip"
GATO_ZIP      = WORK / "alicia_wonderland_gato.zip"

IMG_BUCKET     = "wallpaper-images"
SCENES_BUCKET  = "wallpaper-scenes"
SPRITES_BUCKET = "wallpaper-sprites"

R_BG       = "alicia_wonderland_bg.webp"
R_FLAT     = "alicia_wonderland.webp"
R_PREVIEW  = "alicia_wonderland_preview.webp"
R_SPEC     = "alicia_wonderland.json"
R_CATALOG  = "catalog_index.json"
R_MANIFEST = "manifest.json"

SCENE_ID  = "alicia_wonderland"
STATIC_ID = "alicia_wonderland_scene"

ALICIA_KEY = "alicia_wonderland/alicia"
GATO_KEY   = "alicia_wonderland/gato"

TAGS = ["alicia", "cultura", "anime", "peliculas", "disney", "fantasia",
        "gato", "cheshire", "bosque", "3d", "parallax"]
GLOW = "#7B5CFF"  # violeta mágico del País de las Maravillas
CATEGORY = "cultura"

# Posiciones default: como los sprites son 1080x1920 (mismo canvas que el
# fondo) y traen a Alicia/gato en su lugar original, x/y=0.5 + scale=1.0
# reconstruye la composición. El usuario afina en el editor.
ALICIA_POS = {"x": 0.5, "y": 0.5, "scale": 1.0}
GATO_POS   = {"x": 0.5, "y": 0.5, "scale": 1.0}

# ── Códice cultural (formato CulturalContent) ──────────────────────────────
CULTURAL = {
    "chapter": "Capítulo · País de las Maravillas",
    "subtitle": "El sueño que reinventó la fantasía",
    "lead": "En 1865, el matemático de Oxford Charles Dodgson —bajo el "
            "seudónimo de Lewis Carroll— publicó el cuento que había improvisado "
            "para tres niñas durante un paseo en bote. Alicia sigue a un Conejo "
            "Blanco por su madriguera y cae en un mundo donde la lógica se "
            "invierte: crece, encoge y conversa con un Gato de Cheshire que "
            "aparece y desaparece dejando flotando solo su sonrisa.",
    "facts": [
        {"key": "Autor",        "value": "Lewis Carroll · 1865"},
        {"key": "Título orig.", "value": "Alice's Adventures in Wonderland"},
        {"key": "Origen",       "value": "Paseo en bote · 4 jul 1862"},
        {"key": "Musa",         "value": "Alice Liddell · 10 años"},
        {"key": "Ilustrador",   "value": "John Tenniel"},
        {"key": "Secuela",      "value": "A través del espejo · 1871"},
    ],
    "ofrenda": {
        "label": "Curiosidad",
        "text": "Existe un trastorno neurológico real llamado 'Síndrome de "
                "Alicia en el País de las Maravillas' (1955): quien lo padece "
                "percibe su cuerpo y los objetos más grandes o más pequeños de "
                "lo que son — justo como le pasaba a Alicia.",
    },
    "cta": "Entrar al País de las Maravillas",
}


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
    print("\n[1/5] Procesamiento local")
    WORK.mkdir(parents=True, exist_ok=True)
    info = {}

    # 1a. Background (solofondo, opaco) -> WebP
    bg = Image.open(SRC_BG).convert("RGB")
    info["bg_w"], info["bg_h"] = bg.width, bg.height
    bg.save(OUT_BG_WEBP, "WEBP", quality=90, method=6)
    info["bg_size"] = OUT_BG_WEBP.stat().st_size
    print(f"  · bg {bg.width}x{bg.height}, {info['bg_size']:,} B")

    # 1b. Flat fallback + preview de la composición COMPLETA (con Alicia+gato),
    # así el grid y los clientes sin canvas_scene ven la escena armada.
    flat = Image.open(SRC_FLAT).convert("RGB")
    flat.save(OUT_FLAT_WEBP, "WEBP", quality=88, method=6)
    info["flat_size"] = OUT_FLAT_WEBP.stat().st_size
    prev = flat.copy(); prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_PREV_WEBP, "WEBP", quality=85, method=6)
    info["prev_size"] = OUT_PREV_WEBP.stat().st_size
    print(f"  · flat {flat.width}x{flat.height} {info['flat_size']:,} B · "
          f"preview {prev.width}x{prev.height} {info['prev_size']:,} B")

    # 1c. Sprites estáticos (1 frame cada uno) -> ZIP con frame_001.png
    def one_frame_zip(src_png: Path, out_zip: Path, label: str):
        img = Image.open(src_png).convert("RGBA")
        fbuf = io.BytesIO(); img.save(fbuf, "PNG", optimize=True)
        data = fbuf.getvalue()
        zbuf = io.BytesIO()
        with zipfile.ZipFile(zbuf, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("frame_001.png", data)
        out_zip.write_bytes(zbuf.getvalue())
        print(f"  · {label}: 1 frame {img.width}x{img.height}, "
              f"png={len(data):,} B, zip={out_zip.stat().st_size:,} B")
        return {"frames": 1, "zip_size": out_zip.stat().st_size}

    info["alicia"] = one_frame_zip(SRC_ALICIA, ALICIA_ZIP, "Alicia")
    info["gato"]   = one_frame_zip(SRC_GATO, GATO_ZIP, "Gato Cheshire")
    return info


# ───────────────────── FASE 2: upload assets ─────────────────────
def phase2_upload(info):
    print("\n[2/5] Upload assets")
    put(IMG_BUCKET, R_BG, OUT_BG_WEBP, "image/webp")
    put(IMG_BUCKET, R_FLAT, OUT_FLAT_WEBP, "image/webp")
    put(IMG_BUCKET, R_PREVIEW, OUT_PREV_WEBP, "image/webp")
    put(SPRITES_BUCKET, "alicia_wonderland_alicia.zip", ALICIA_ZIP, "application/zip")
    put(SPRITES_BUCKET, "alicia_wonderland_gato.zip", GATO_ZIP, "application/zip")


# ───────────────────── FASE 3: sprite manifest ─────────────────────
def phase3_manifest(info):
    print("\n[3/5] Update wallpaper-sprites/manifest.json")
    manifest = get_json(SPRITES_BUCKET, R_MANIFEST)
    manifest[ALICIA_KEY] = {
        "zip": "alicia_wonderland_alicia.zip",
        "frames": 1, "size": info["alicia"]["zip_size"],
    }
    manifest[GATO_KEY] = {
        "zip": "alicia_wonderland_gato.zip",
        "frames": 1, "size": info["gato"]["zip_size"],
    }
    print(f"  · manifest now has {len(manifest)} entries (+2)")
    put_json(SPRITES_BUCKET, R_MANIFEST, manifest)


# ───────────────────── FASE 4: scene spec ─────────────────────
def phase4_spec(info):
    print("\n[4/5] Create + upload scene spec")
    url_bg   = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_BG}"
    url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_FLAT}"
    url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}"

    spec = {
        "schema_version": 1,
        "id": SCENE_ID,
        "type": "canvas_scene",
        "title": {"en": "Alice in Wonderland", "es": "Alicia en el País de las Maravillas"},
        "tags": TAGS,
        "category": CATEGORY,
        "featured": True,
        "background": {"url": url_flat, "preview_url": url_prev, "scroll": False},
        "image_layers": [
            {"key": "bg", "url": url_bg, "parallax_factor": 0.0,
             "scroll_factor": 0.0, "z": 0, "scale": 1.0},
        ],
        # Gato detrás (array primero), Alicia al frente. Gato fijo, Alicia con
        # parallax leve. El usuario afina posiciones/parallax en el editor.
        "sprites": [
            {"name": "gato_cheshire", "manifest_key": GATO_KEY,
             "behavior": "static", "frame_skip": 4,
             "params": {"x": GATO_POS["x"], "y": GATO_POS["y"],
                        "scale": GATO_POS["scale"], "alpha": 255,
                        "parallax_factor": 0.0, "z": 1}},
            {"name": "alicia", "manifest_key": ALICIA_KEY,
             "behavior": "static", "frame_skip": 4,
             "params": {"x": ALICIA_POS["x"], "y": ALICIA_POS["y"],
                        "scale": ALICIA_POS["scale"], "alpha": 255,
                        "parallax_factor": 0.03, "z": 2}},
        ],
        "particles": [],
        "events": [],
    }
    KNOWN = {'orbit', 'wander', 'translate', 'static', 'preload'}
    for sp in spec['sprites']:
        assert sp['behavior'] in KNOWN, f"behavior {sp['behavior']} fuera de vocab"
    print("  · spec validado (2 sprites + 1 image_layer)")
    put_json(SCENES_BUCKET, R_SPEC, spec)
    return spec


# ───────────────────── FASE 5: catalog_index + Postgres ─────────────────────
def phase5_catalog_and_postgres(info, spec):
    print("\n[5/5] catalog_index.json + Postgres")
    cat = get_json(IMG_BUCKET, R_CATALOG)
    cat["version"] = (cat.get("version", 0) or 0) + 1
    entry = {
        "id": SCENE_ID,
        "type": "canvas_scene",
        "schema": 1,
        "title": spec["title"],
        "preview_url": f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}",
        "tags": TAGS,
        "category": CATEGORY,
        "featured": True,
        "cultural": CULTURAL,
        "spec_url": f"{PROJECT}/storage/v1/object/public/{SCENES_BUCKET}/{R_SPEC}",
    }
    items = cat.get("items", [])
    idx = next((i for i, it in enumerate(items) if it.get("id") == SCENE_ID), -1)
    if idx >= 0:
        items[idx] = entry; print(f"  · catalog_index: {SCENE_ID} replace")
    else:
        items.append(entry); print(f"  · catalog_index: {SCENE_ID} append (total {len(items)})")
    cat["items"] = items
    put_json(IMG_BUCKET, R_CATALOG, cat)
    print(f"  · catalog version -> {cat['version']}")

    # Postgres: type=static + category=SCENES (cliente lo resuelve como
    # canvas_scene). published=true; sin FCM aún (se dispara cuando el usuario
    # guarde en el editor). cultural column también, por consistencia.
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    # cultural NO va en Postgres — los canvas_scene lo leen del catalog_index
    # (ya subido en 5a). La tabla wallpapers no tiene columna cultural.
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
        STATIC_ID, "Alicia en el País de las Maravillas",
        "Alicia y el Gato de Cheshire en un bosque mágico, con efecto 3D parallax. "
        "Incluye su códice cultural.",
        TAGS, R_FLAT, R_PREVIEW, info["flat_size"], info["prev_size"], GLOW,
        next_sort, "Pixora Studio", info["bg_w"], info["bg_h"]
    ))
    print(f"  · postgres upserted: {cur.fetchone()[0]}")
    conn.commit(); cur.close(); conn.close()


if __name__ == "__main__":
    print("=" * 60)
    print("Alicia en el País de las Maravillas — canvas_scene publisher")
    print("=" * 60)
    for src in (SRC_BG, SRC_FLAT, SRC_ALICIA, SRC_GATO):
        if not src.exists():
            raise SystemExit(f"No existe {src}")
    info = phase1_process()
    phase2_upload(info)
    phase3_manifest(info)
    spec = phase4_spec(info)
    phase5_catalog_and_postgres(info, spec)
    print("\n" + "=" * 60)
    print("Alicia publicada como canvas_scene (borrador para editor)")
    print(f"  · scene_id: {SCENE_ID}")
    print(f"  · sprites: Alicia + Gato Cheshire (1 frame c/u, estáticos)")
    print(f"  · spec: wallpaper-scenes/{R_SPEC}")
    print(f"  · SIN FCM — se dispara cuando guardes posiciones en el editor")
    print("=" * 60)
    print("\nAbre el sprite editor: http://localhost:5758/sprite-editor.html")
    print(f"Selecciona '{SCENE_ID}', posiciona Gato (fijo) + Alicia (parallax), guarda.")
