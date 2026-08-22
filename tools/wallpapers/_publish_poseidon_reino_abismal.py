"""Publica la escena Poseidón después de QA en Huawei y Samsung."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


SID = "poseidon_reino_abismal"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"poseidon_reino_abismal_20260818"
)


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    layers = spec.get("image_layers", [])
    if len(matches) != 1 or len(layers) != 2:
        raise RuntimeError("Inventario remoto inesperado")
    background = next((layer for layer in layers if layer.get("key") == "background"), None)
    poseidon = next((layer for layer in layers if layer.get("key") == "poseidon"), None)
    if not background or not poseidon:
        raise RuntimeError("Faltan capas canónicas")
    if abs(float(background.get("scale", 0)) - 1.26) > 0.001:
        raise RuntimeError("La cobertura aprobada del fondo cambió")
    if int(background.get("revision", 0)) != 2 or int(poseidon.get("revision", 0)) != 2:
        raise RuntimeError("La revisión aprobada cambió")

    qa_captures = [
        ROOT / "preview" / "huawei_qa_v2.png",
        ROOT / "preview" / "samsung_qa_applied.png",
    ]
    if not all(path.is_file() and path.stat().st_size > 100_000 for path in qa_captures):
        raise RuntimeError("Falta evidencia QA de Huawei o Samsung")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    db_before = cur.fetchone()
    if not db_before:
        cur.close()
        conn.close()
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
        cur.execute(
            "UPDATE wallpapers SET published=%s WHERE id=%s",
            (bool(db_before[0]), SID),
        )
        conn.commit()
        cur.close()
        conn.close()
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
        "qa_devices": ["HUAWEI VNS-L53", "Samsung SM-A155M"],
        "qa_captures": [str(path.relative_to(ROOT)).replace("\\", "/") for path in qa_captures],
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
