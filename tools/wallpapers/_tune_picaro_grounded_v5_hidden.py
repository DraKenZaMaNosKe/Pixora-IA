"""Ajusta a Pícaro para que ambos pies descansen en el piso junto a la puerta."""
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
EXPECTED = {"x": 0.60, "y": 0.75, "z": 30, "parallax_factor": 0.07}
NEW = {"x": 0.55, "y": 0.75, "z": 30, "parallax_factor": 0.07}


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    if int(catalog.get("version", 0) or 0) != 245:
        raise RuntimeError("La versión inicial del catálogo cambió")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1 or spec.get("published") is not False or matches[0].get("published") is not False:
        raise RuntimeError("La escena no parte del estado oculto esperado")
    if len(spec.get("sprites", [])) != 1:
        raise RuntimeError("Inventario de sprites inesperado")
    sprite = spec["sprites"][0]
    params = sprite.get("params", {})
    if sprite.get("manifest_key") != "picaro_puerta_roja_blink":
        raise RuntimeError("Manifest inesperado")
    for key, value in EXPECTED.items():
        if abs(float(params.get(key, -999)) - value) > 0.001:
            raise RuntimeError(f"El valor inicial {key} cambió")
    layers = spec.get("image_layers", [])
    if {layer.get("key") for layer in layers} != {"background", "foreground_door"}:
        raise RuntimeError("Capas inesperadas")
    if any(int(layer.get("revision", 0)) != 2 for layer in layers):
        raise RuntimeError("Revisión visual inesperada")
    door = next(layer for layer in layers if layer.get("key") == "foreground_door")
    if int(door.get("z", -1)) != 20 or abs(float(door.get("parallax_factor", -1)) - 0.07) > 0.001:
        raise RuntimeError("La geometría de la puerta cambió")

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

        remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == SID]
        remote_params = remote_spec["sprites"][0]["params"]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        remote_db = cur.fetchone()
        if (
            remote_spec.get("published") is not False
            or len(remote_matches) != 1
            or remote_matches[0].get("published") is not False
            or not remote_db
            or bool(remote_db[0]) is not False
        ):
            raise RuntimeError("La escena dejó de estar oculta en algún plano")
        for key, value in NEW.items():
            if abs(float(remote_params.get(key, -999)) - value) > 0.001:
                raise RuntimeError(f"Falló la verificación remota de {key}")
        receipt = {
            "scene_id": SID,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "catalog_version": remote_catalog.get("version"),
            "published": False,
            "sprite_params": NEW,
            "composition": "full_body_both_feet_on_floor_beside_door",
            "fcm_catalog_invalidate": fcm,
        }
        (ROOT / "PICARO_GROUNDED_V5_DRAFT.json").write_text(
            json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (ROOT / "PICARO_GROUNDED_V5_RECEIPT.json").write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except Exception:
        put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        cur.close()
        conn.close()
        raise

    cur.close()
    conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
