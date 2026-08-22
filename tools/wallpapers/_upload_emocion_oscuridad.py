"""Publica en produccion la escena AMOLED original Emocion en la oscuridad."""
from __future__ import annotations

import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import PROJECT, get_json, put, put_json
from apply_migration import connect

SCENE_ID = "emocion_oscuridad_amoled"
SPRITE_KEY = "emocion_oscuridad_face_v1"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/3_publicados/emocion_oscuridad_amoled")
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"
SPRITES_BUCKET = "wallpaper-sprites"


def public(bucket: str, name: str) -> str:
    return f"{PROJECT}/storage/v1/object/public/{bucket}/{name}"


def main() -> None:
    bg = ROOT / "production/background.webp"
    flat = ROOT / "production/emocion_oscuridad_amoled.webp"
    preview = ROOT / "emocion_oscuridad_preview_540x1170.webp"
    sprite_zip = ROOT / "production/emocion_oscuridad_face_v1.zip"
    for path in (bg, flat, preview, sprite_zip):
        if not path.is_file():
            raise FileNotFoundError(path)

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT id, published FROM wallpapers WHERE id = %s", (SCENE_ID,))
    existing = cur.fetchone()
    if existing:
        raise RuntimeError(f"La escena ya existe en Postgres: {existing}")

    names = {
        "bg": f"{SCENE_ID}_background.webp",
        "flat": f"{SCENE_ID}.webp",
        "preview": f"{SCENE_ID}_preview.webp",
        "spec": f"{SCENE_ID}.json",
        "zip": "emocion_oscuridad_face_v1.zip",
    }

    print("[1/6] Subiendo recursos")
    put(IMG_BUCKET, names["bg"], bg.read_bytes())
    put(IMG_BUCKET, names["flat"], flat.read_bytes())
    put(IMG_BUCKET, names["preview"], preview.read_bytes())
    put(SPRITES_BUCKET, names["zip"], sprite_zip.read_bytes(), "application/zip")

    print("[2/6] Actualizando manifiesto de sprites")
    manifest = get_json(SPRITES_BUCKET, "manifest.json")
    manifest[SPRITE_KEY] = {
        "zip": names["zip"],
        "frames": 93,
        "size": sprite_zip.stat().st_size,
    }
    put_json(SPRITES_BUCKET, "manifest.json", manifest)

    title = {"es": "Emoción en la oscuridad", "en": "Emotion in the Dark"}
    tags = ["amoled", "emociones", "ojos", "oscuridad", "original", "sprite", "expresiones"]
    plain = (
        "Umbra, una presencia original nacida de la oscuridad, cambia lentamente "
        "entre alegría, enojo, tristeza, sueño, sorpresa y una sonrisa traviesa."
    )
    rich = (
        "[[name:Umbra]] es una creación original de Pixora IA: una presencia abstracta "
        "cuyo rostro sólo existe mediante ojos y boca. El negro puede representar silencio, "
        "descanso y misterio; al retirar todo lo demás, el cerebro completa automáticamente "
        "al personaje. Sus expresiones recorren atención, alegría, enojo, tristeza, sueño, "
        "cansancio, sorpresa y picardía. El fondo negro puro favorece las pantallas AMOLED, "
        "donde los píxeles negros pueden apagarse, aunque el consumo final depende del brillo "
        "y del uso del dispositivo. Umbra no pertenece a ninguna película, anime o videojuego."
    )
    spec = {
        "schema_version": 1,
        "id": SCENE_ID,
        "type": "canvas_scene",
        "title": title,
        "category": "abstract",
        "featured": False,
        "published": True,
        "tags": tags,
        "background": {
            "url": public(IMG_BUCKET, names["flat"]),
            "preview_url": public(IMG_BUCKET, names["preview"]),
            "scroll": False,
        },
        "image_layers": [{
            "key": "background", "url": public(IMG_BUCKET, names["bg"]), "z": 0,
            "parallax_factor": 0.0, "scroll_factor": 0.0, "scale": 1.0,
            "offset_x_px": 0, "offset_y_px": 0, "revision": 1,
        }],
        "sprites": [{
            "name": "shadow_face", "manifest_key": SPRITE_KEY,
            "behavior": "static", "frame_skip": 10,
            "params": {"x": 0.5, "y": 0.34, "scale": 0.003, "alpha": 255, "z": 10},
        }],
        "particles": [], "cycles": [], "events": [],
        "branding": {"enabled": True},
        "performance": {
            "amoled_black_background": True, "sprite_source_size": [512, 384],
            "runtime_sample_size": 2, "unique_expressions": 9, "sequence_frames": 93,
        },
    }
    print("[3/6] Publicando especificación")
    put_json(SCENES_BUCKET, names["spec"], spec)

    print("[4/6] Registrando Postgres")
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers")
    sort_order = cur.fetchone()[0]
    cur.execute(
        """
        INSERT INTO wallpapers (
          id, name, description, description_rich, type, category, tags,
          image_path, preview_path, image_size, preview_size, glow_color,
          badge, sort_order, featured, trending_score, published, daily_eligible,
          author_name, media_width, media_height
        ) VALUES (
          %s, %s, %s, %s, 'static'::wallpaper_type, 'SCENES'::wallpaper_category, %s,
          %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, false, 0, true, false,
          'Pixora Studio', 1080, 2340
        )
        """,
        (SCENE_ID, title["es"], plain, rich, tags, names["flat"], names["preview"],
         flat.stat().st_size, preview.stat().st_size, "#BDEBFF", sort_order),
    )
    conn.commit()

    print("[5/6] Publicando en catálogo")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    entry = {
        "id": SCENE_ID, "type": "canvas_scene", "schema": 1, "title": title,
        "preview_url": public(IMG_BUCKET, names["preview"]),
        "image_url": public(IMG_BUCKET, names["flat"]),
        "tags": tags, "category": "abstract", "featured": False,
        "glow_color": "#BDEBFF", "published": True, "description": plain,
        "spec_url": public(SCENES_BUCKET, names["spec"]),
    }
    catalog["items"] = [entry] + [x for x in catalog.get("items", []) if x.get("id") != SCENE_ID]
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    print("[6/6] Guardando recibo e invalidando caché")
    (ROOT / "SCENE_SPEC_PRODUCTION.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    fcm = send_catalog_invalidate("wallpapers")
    receipt = {
        "scene_id": SCENE_ID, "published_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": catalog["version"], "sprite_frames": 93,
        "fcm_catalog_invalidate": fcm,
        "spec_url": public(SCENES_BUCKET, names["spec"]),
    }
    (ROOT / "PRODUCTION_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    cur.close()
    conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
