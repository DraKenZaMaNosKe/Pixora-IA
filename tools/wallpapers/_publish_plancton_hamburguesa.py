"""Publica Plancton con hamburguesa después de la aprobación en Huawei."""
from __future__ import annotations

import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


SID = "plancton_hamburguesa_escape"
MANIFEST_KEY = "plancton_hamburguesa_escape_plancton"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/plancton_hamburguesa_escape")
PUBLIC = "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public"


def head_size(url: str) -> int:
    req = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(req, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f"HEAD fallo: {response.status} {url}")
        return int(response.headers.get("Content-Length", 0))


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1:
        raise RuntimeError(f"Entradas de catálogo inesperadas: {len(matches)}")

    sprites = spec.get("sprites", [])
    layers = spec.get("image_layers", [])
    if len(sprites) != 1 or len(layers) != 1:
        raise RuntimeError("Inventario de escena inesperado")
    sprite = sprites[0]
    params = sprite.get("params", {})
    if sprite.get("manifest_key") != MANIFEST_KEY:
        raise RuntimeError("Manifest de sprite inesperado")
    if sprite.get("frame_skip") != 12 or params.get("high_res") is not False:
        raise RuntimeError("Configuración de rendimiento inesperada")
    if abs(float(params.get("x", 0)) - 0.49805304247265453) > 0.000001:
        raise RuntimeError("La posición X aprobada cambió")
    if abs(float(params.get("y", 0)) - 0.8612303224712381) > 0.000001:
        raise RuntimeError("La posición Y aprobada cambió")
    if abs(float(params.get("scale", 0)) - 0.003) > 0.000001:
        raise RuntimeError("La escala aprobada cambió")

    background = layers[0]
    if background.get("key") != "background" or abs(float(background.get("scale", 0)) - 1.24) > 0.001:
        raise RuntimeError("La cobertura final del fondo cambió")

    manifest = get_json("wallpaper-sprites", "manifest.json")
    manifest_entry = manifest.get(MANIFEST_KEY, {})
    if int(manifest_entry.get("frames", 0)) != 15:
        raise RuntimeError("El manifest no confirma los 15 cuadros")

    image_size = head_size(f"{PUBLIC}/{IMG_BUCKET}/{SID}.webp")
    preview_size = head_size(f"{PUBLIC}/{IMG_BUCKET}/{SID}_preview.webp")
    background_size = head_size(f"{PUBLIC}/{IMG_BUCKET}/{SID}_background.webp")
    sprite_zip_size = head_size(f"{PUBLIC}/wallpaper-sprites/{MANIFEST_KEY}.zip")

    spec["published"] = True
    matches[0]["published"] = True
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    conn = connect()
    cur = conn.cursor()
    cur.execute(
        "UPDATE wallpapers SET published=true, image_size=%s, preview_size=%s WHERE id=%s RETURNING id,published",
        (image_size, preview_size, SID),
    )
    row = cur.fetchone()
    if not row:
        conn.rollback()
        raise RuntimeError("No existe la fila en Postgres")
    conn.commit()
    fcm = send_catalog_invalidate("wallpapers")

    remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
    remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == SID]
    if not remote_spec.get("published") or len(remote_matches) != 1 or not remote_matches[0].get("published"):
        raise RuntimeError("Falló la verificación remota de publicación")

    receipt = {
        "scene_id": SID,
        "published_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": remote_catalog.get("version"),
        "catalog_published": bool(remote_matches[0].get("published")),
        "scene_spec_published": bool(remote_spec.get("published")),
        "postgres_published": bool(row[1]),
        "sprite_frames": manifest_entry.get("frames"),
        "sprite_position": {"x": params.get("x"), "y": params.get("y")},
        "sprite_scale": params.get("scale"),
        "frame_skip": sprite.get("frame_skip"),
        "background_scale": background.get("scale"),
        "asset_sizes": {
            "flat": image_size,
            "preview": preview_size,
            "background": background_size,
            "sprite_zip": sprite_zip_size,
        },
        "qa_device": "HUAWEI VNS-L53",
        "qa_capture": "qa/HUAWEI_QA_V3.png",
        "qa_no_new_oom_or_fatal": True,
        "fcm_catalog_invalidate": fcm,
    }
    (ROOT / "SCENE_SPEC_PRODUCTION.json").write_text(
        json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "PRODUCTION_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    cur.close()
    conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
