"""Publica la escena aprobada gatito_curioso_parpadeo y verifica producción."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


SID = "gatito_curioso_parpadeo"
MANIFEST_KEY = "gatito_curioso_parpadeo_gatito"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_curioso_parpadeo_20260812")


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1:
        raise RuntimeError(f"Se esperaba una entrada de catálogo, encontradas={len(matches)}")

    sprites = spec.get("sprites", [])
    layers = spec.get("image_layers", [])
    if len(sprites) != 1 or len(layers) != 1:
        raise RuntimeError("Inventario de escena inesperado")
    sprite = sprites[0]
    params = sprite.get("params", {})
    if sprite.get("manifest_key") != MANIFEST_KEY or sprite.get("frame_skip") != 8:
        raise RuntimeError("Configuración del sprite inesperada")
    expected = {"x": 0.095, "y": 0.825, "scale": 0.00235, "parallax_factor": 0.0}
    for key, value in expected.items():
        if abs(float(params.get(key, -999)) - value) > 0.000001:
            raise RuntimeError(f"El valor aprobado de {key} cambió")
    if abs(float(layers[0].get("parallax_factor", -999))) > 0.000001:
        raise RuntimeError("El fondo volvió a tener movimiento lateral")

    spec["published"] = True
    matches[0]["published"] = True
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    conn = connect()
    cur = conn.cursor()
    cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING id,published", (SID,))
    row = cur.fetchone()
    if not row:
        conn.rollback()
        raise RuntimeError("No existe la escena en Postgres")
    conn.commit()
    cur.close()
    conn.close()

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
        "scene_spec_published": True,
        "catalog_published": True,
        "postgres_published": bool(row[1]),
        "sprite_position": {"x": params["x"], "y": params["y"]},
        "sprite_scale": params["scale"],
        "frame_skip": sprite["frame_skip"],
        "fcm_catalog_invalidate": fcm,
        "qa_device": "HUAWEI VNS-L53",
        "qa_capture": "qa_wall_close/huawei_alineado_2.png",
    }
    (ROOT / "SCENE_SPEC_PRODUCTION.json").write_text(
        json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ROOT / "PRODUCTION_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
