"""Recompone Pícaro con cuerpo completo, al nivel del piso y delante de la puerta."""
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
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/picaro_puerta_roja_20260818")
NEW = {"x": 0.60, "y": 0.75, "z": 30, "parallax_factor": 0.07}


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1 or spec.get("published") is not False or matches[0].get("published") is not False:
        raise RuntimeError("La escena no parte del estado oculto esperado")
    if len(spec.get("sprites", [])) != 1:
        raise RuntimeError("Inventario de sprites inesperado")
    sprite = spec["sprites"][0]
    params = sprite.get("params", {})
    if sprite.get("manifest_key") != "picaro_puerta_roja_blink":
        raise RuntimeError("Manifest inesperado")
    expected = {"x": 0.55, "y": 0.65, "z": 10, "parallax_factor": 0.07}
    for key, value in expected.items():
        if abs(float(params.get(key, -999)) - value) > 0.001:
            raise RuntimeError(f"El valor inicial {key} cambió")
    layers = spec.get("image_layers", [])
    if {layer.get("key") for layer in layers} != {"background", "foreground_door"}:
        raise RuntimeError("Capas inesperadas")
    if any(int(layer.get("revision", 0)) != 2 for layer in layers):
        raise RuntimeError("Revisión visual inesperada")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    db_before = cur.fetchone()
    if not db_before or bool(db_before[0]) is not False:
        raise RuntimeError("Postgres no está oculto")
    spec_before = json.loads(json.dumps(spec))
    catalog_before = json.loads(json.dumps(catalog))
    try:
        params.update(NEW)
        catalog["version"] = int(catalog.get("version", 0) or 0) + 1
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        fcm = send_catalog_invalidate("wallpapers")
    except Exception:
        put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        cur.close()
        conn.close()
        raise

    remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
    remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    remote_params = remote_spec["sprites"][0]["params"]
    if remote_spec.get("published") is not False:
        raise RuntimeError("La escena dejó de estar oculta")
    for key, value in NEW.items():
        if abs(float(remote_params.get(key, -999)) - value) > 0.001:
            raise RuntimeError(f"Falló la verificación remota de {key}")
    receipt = {
        "scene_id": SID,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": remote_catalog.get("version"),
        "published": False,
        "sprite_params": NEW,
        "composition": "full_body_in_front_of_door_grounded",
        "fcm_catalog_invalidate": fcm,
    }
    (ROOT / "PICARO_FULL_BODY_QA_DRAFT.json").write_text(
        json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "PICARO_FULL_BODY_QA_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    cur.close()
    conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
