"""Promueve El aquelarre de los nueve bigotes de QA privado a produccion."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import get_json, put_json, IMG_BUCKET, SCENES_BUCKET


SID = "aquelarre_nueve_bigotes_parallax"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/aquelarre_nueve_bigotes_parallax")


def main() -> None:
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1:
        raise RuntimeError(f"Entradas de catalogo encontradas: {len(matches)}")
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    layers = spec.get("image_layers", [])
    if len(layers) != 9 or len(spec.get("cycles", [])) != 2:
        raise RuntimeError("Inventario inesperado: se cancela la publicacion")
    if any(abs(float(layer.get("scale", 0)) - 1.24) > 0.001 for layer in layers):
        raise RuntimeError("Alguna capa no conserva la escala de cobertura 1.24")
    if any(abs(float(layer.get("parallax_factor", 0)) - 0.10) > 0.001 for layer in layers):
        raise RuntimeError("Alguna capa puede desalinearse del grabado base")

    matches[0]["published"] = True
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    spec["published"] = True
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    conn = connect(); cur = conn.cursor()
    cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING id,published", (SID,))
    row = cur.fetchone()
    if not row:
        conn.rollback()
        raise RuntimeError("No existe la fila de Postgres")
    conn.commit()
    fcm = send_catalog_invalidate("wallpapers")

    receipt = {
        "scene_id": SID,
        "published_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": catalog["version"],
        "catalog_published": bool(matches[0]["published"]),
        "scene_spec_published": bool(spec["published"]),
        "postgres_published": bool(row[1]),
        "fcm_catalog_invalidate": fcm,
        "qa_device": "HUAWEI VNS-L53",
        "qa_capture": "qa/QA_AQUELARRE_FINAL_124.png",
        "image_layers": 9,
        "cycles": 2,
        "coverage_scale": 1.24,
    }
    (ROOT / "SCENE_SPEC_PRODUCTION.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "PRODUCTION_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    cur.close(); conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
