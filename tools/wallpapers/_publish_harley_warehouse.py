"""Promueve Harley Quinn Almacen de QA oculto a producción."""
from __future__ import annotations
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import get_json, put_json, IMG_BUCKET, SCENES_BUCKET

SID = "harley_quinn_warehouse_parallax"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/harley_quinn_warehouse_parallax")


def main():
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [x for x in catalog.get("items", []) if x.get("id") == SID]
    if len(matches) != 1:
        raise RuntimeError(f"Se esperaba una entrada de catálogo; encontradas: {len(matches)}")
    matches[0]["published"] = True
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1

    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    if len(spec.get("image_layers", [])) != 6 or len(spec.get("cycles", [])) != 1:
        raise RuntimeError("Spec inesperado: se cancela la promoción")
    spec["published"] = True

    conn = connect(); cur = conn.cursor()
    cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING id,published", (SID,))
    row = cur.fetchone()
    if not row:
        raise RuntimeError("No existe la fila de Postgres")
    conn.commit()

    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    put_json(IMG_BUCKET, "catalog_index.json", catalog)
    fcm = send_catalog_invalidate("wallpapers")

    (ROOT / "SCENE_SPEC_PRODUCTION.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    receipt = {
        "scene_id": SID,
        "published_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": catalog["version"],
        "postgres_published": bool(row[1]),
        "fcm_catalog_invalidate": fcm,
        "qa_devices": ["HUAWEI VNS-L53", "Samsung SM-A155M"],
        "image_layers": 6,
        "cycles": 1,
    }
    (ROOT / "PRODUCTION_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    cur.close(); conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
