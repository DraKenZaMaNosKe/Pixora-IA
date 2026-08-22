"""Oculta Pícaro y fija el gato a la puerta para una nueva ronda de QA."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


SID = "picaro_puerta_roja"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"picaro_puerta_roja_20260818"
)
NEW_X = 0.55
LOCKED_PARALLAX = 0.07


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1 or len(spec.get("sprites", [])) != 1:
        raise RuntimeError("Inventario remoto inesperado")
    sprite = spec["sprites"][0]
    params = sprite.get("params", {})
    if sprite.get("manifest_key") != "picaro_puerta_roja_blink":
        raise RuntimeError("Manifest de Pícaro inesperado")
    if abs(float(params.get("x", 0)) - 0.55) > 0.001:
        raise RuntimeError("La posición inicial ya no coincide con la versión auditada")
    if abs(float(params.get("parallax_factor", 0)) - 0.07) > 0.001:
        raise RuntimeError("El paralaje inicial ya no coincide con la versión auditada")
    layers = spec.get("image_layers", [])
    if {layer.get("key") for layer in layers} != {"background", "foreground_door"}:
        raise RuntimeError("Capas inesperadas")
    if any(int(layer.get("revision", 0)) != 2 for layer in layers):
        raise RuntimeError("La revisión visual cambió")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    db_before = cur.fetchone()
    if not db_before:
        raise RuntimeError("No existe la fila Postgres")
    spec_before = json.loads(json.dumps(spec))
    catalog_before = json.loads(json.dumps(catalog))

    try:
        params["x"] = NEW_X
        params["parallax_factor"] = LOCKED_PARALLAX
        spec["published"] = False
        matches[0]["published"] = False
        catalog["version"] = int(catalog.get("version", 0) or 0) + 1
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute(
            "UPDATE wallpapers SET published=false WHERE id=%s RETURNING published",
            (SID,),
        )
        row = cur.fetchone()
        if not row or bool(row[0]) is not False:
            raise RuntimeError("No se pudo ocultar en Postgres")
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
    remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == SID]
    remote_params = remote_spec["sprites"][0]["params"]
    if (
        remote_spec.get("published") is not False
        or len(remote_matches) != 1
        or remote_matches[0].get("published") is not False
        or abs(float(remote_params.get("x", 0)) - NEW_X) > 0.001
        or abs(float(remote_params.get("parallax_factor", 0)) - LOCKED_PARALLAX) > 0.001
    ):
        raise RuntimeError("Falló la verificación remota")

    receipt = {
        "scene_id": SID,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": remote_catalog.get("version"),
        "published": False,
        "sprite_x": NEW_X,
        "sprite_parallax_factor": LOCKED_PARALLAX,
        "reason": "lock_cat_to_foreground_door_for_cross_device_qa",
        "fcm_catalog_invalidate": fcm,
    }
    (ROOT / "PICARO_ATTACHMENT_QA_DRAFT.json").write_text(
        json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "PICARO_ATTACHMENT_QA_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    cur.close()
    conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
