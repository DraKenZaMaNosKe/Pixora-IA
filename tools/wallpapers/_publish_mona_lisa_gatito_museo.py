"""Publica Mona Lisa con gatito después de QA final en Huawei."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


SID = "mona_lisa_gatito_museo"
MANIFEST_KEY = "mona_lisa_gatito_museo_pair"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"mona_lisa_gatito_museo_20260818"
)


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    manifest = get_json("wallpaper-sprites", "manifest.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    layers = spec.get("image_layers", [])
    sprites = spec.get("sprites", [])
    if len(matches) != 1 or len(layers) != 1 or len(sprites) != 1:
        raise RuntimeError("Inventario remoto inesperado")
    background = layers[0]
    sprite = sprites[0]
    pack = manifest.get(MANIFEST_KEY)
    if background.get("key") != "background" or abs(float(background.get("scale", 0)) - 1.26) > 0.001:
        raise RuntimeError("La cobertura aprobada cambió")
    if int(background.get("revision", 0)) != 3:
        raise RuntimeError("La revisión aprobada cambió")
    if sprite.get("manifest_key") != MANIFEST_KEY or not isinstance(pack, dict) or int(pack.get("frames", 0)) != 5:
        raise RuntimeError("Paquete animado inesperado")
    qa_capture = ROOT / "qa" / "HUAWEI_QA_V3.png"
    if not qa_capture.is_file() or qa_capture.stat().st_size < 100_000:
        raise RuntimeError("Falta evidencia QA final de Huawei")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    db_before = cur.fetchone()
    if not db_before:
        cur.close(); conn.close()
        raise RuntimeError("No existe la fila en Postgres")
    spec_before = json.loads(json.dumps(spec))
    catalog_before = json.loads(json.dumps(catalog))

    try:
        spec["published"] = True
        matches[0]["published"] = True
        catalog["version"] = int(catalog.get("version", 0) or 0) + 1
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute(
            "UPDATE wallpapers SET published=true WHERE id=%s RETURNING id,published",
            (SID,),
        )
        row = cur.fetchone()
        if not row:
            raise RuntimeError("No se pudo actualizar Postgres")
        conn.commit()
        fcm = send_catalog_invalidate("wallpapers")
    except Exception:
        conn.rollback()
        put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        cur.execute("UPDATE wallpapers SET published=%s WHERE id=%s", (bool(db_before[0]), SID))
        conn.commit()
        cur.close(); conn.close()
        raise

    remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
    remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    remote_match = [item for item in remote_catalog.get("items", []) if item.get("id") == SID]
    if not remote_spec.get("published") or len(remote_match) != 1 or not remote_match[0].get("published"):
        raise RuntimeError("Falló la verificación remota")
    receipt = {
        "scene_id": SID,
        "published_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": remote_catalog.get("version"),
        "scene_spec_published": True,
        "catalog_published": True,
        "postgres_published": bool(row[1]),
        "background_scale": background.get("scale"),
        "revision": background.get("revision"),
        "sprite_manifest_key": MANIFEST_KEY,
        "sprite_frames": pack.get("frames"),
        "qa_devices": ["HUAWEI VNS-L53"],
        "qa_capture": str(qa_capture.relative_to(ROOT)).replace("\\", "/"),
        "fcm_catalog_invalidate": fcm,
    }
    (ROOT / "SCENE_SPEC_PRODUCTION.json").write_text(
        json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "PRODUCTION_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    cur.close(); conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
