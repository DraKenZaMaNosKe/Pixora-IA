"""Baja juntos a Zeus y su aura para apoyar las sandalias en la plataforma."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path[:0] = [str(SCRIPT_DIR.parent), str(SCRIPT_DIR)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


SID = "zeus_trono_tormenta"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/zeus_trono_tormenta_20260820")
EXPECTED_CATALOG_VERSION = 249
EXPECTED_OFFSET_Y = 44
OFFSET_Y = 64


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if int(catalog.get("version", 0)) != EXPECTED_CATALOG_VERSION:
        raise RuntimeError("La version del catalogo cambio; detener para evitar sobrescribir trabajo")
    if len(matches) != 1 or spec.get("published") is not False or matches[0].get("published") is not False:
        raise RuntimeError("Zeus no parte del estado oculto esperado")
    layers = spec.get("image_layers", [])
    if {layer.get("key") for layer in layers} != {"background", "lightning_aura", "zeus"}:
        raise RuntimeError("Inventario de capas inesperado")
    by_key = {layer["key"]: layer for layer in layers}
    for key in ("lightning_aura", "zeus"):
        layer = by_key[key]
        if int(layer.get("revision", 0)) != 1 or int(layer.get("offset_y_px", -1)) != EXPECTED_OFFSET_Y:
            raise RuntimeError(f"Estado inicial inesperado en {key}")
        if abs(float(layer.get("parallax_factor", -1)) - 0.18) > 0.001:
            raise RuntimeError(f"Parallax inesperado en {key}")
        if abs(float(layer.get("bob_amplitude_px", -1)) - 1.2) > 0.001:
            raise RuntimeError(f"Bob inesperado en {key}")
        if abs(float(layer.get("bob_period_sec", -1)) - 7.4) > 0.001:
            raise RuntimeError(f"Periodo inesperado en {key}")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    row = cur.fetchone()
    if not row or bool(row[0]) is not False:
        cur.close()
        conn.close()
        raise RuntimeError("Postgres no esta oculto")

    spec_before = json.loads(json.dumps(spec))
    catalog_before = json.loads(json.dumps(catalog))
    try:
        by_key["lightning_aura"]["offset_y_px"] = OFFSET_Y
        by_key["zeus"]["offset_y_px"] = OFFSET_Y
        catalog["version"] = EXPECTED_CATALOG_VERSION + 1
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        fcm = send_catalog_invalidate("wallpapers")

        remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        remote_db = cur.fetchone()
        remote_layers = {layer["key"]: layer for layer in remote_spec.get("image_layers", [])}
        if (
            remote_spec.get("published") is not False
            or len(remote_matches) != 1
            or remote_matches[0].get("published") is not False
            or not remote_db
            or bool(remote_db[0]) is not False
            or int(remote_catalog.get("version", 0)) != EXPECTED_CATALOG_VERSION + 1
            or any(int(remote_layers[key].get("offset_y_px", -1)) != OFFSET_Y for key in ("lightning_aura", "zeus"))
        ):
            raise RuntimeError("Fallo la verificacion remota del ajuste oculto")

        receipt = {
            "scene_id": SID,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "catalog_version": remote_catalog["version"],
            "published": False,
            "offset_y_px": OFFSET_Y,
            "layers_synced": ["lightning_aura", "zeus"],
            "fcm_catalog_invalidate": fcm,
        }
        (ROOT / "ZEUS_GROUNDED_QA_DRAFT.json").write_text(
            json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (ROOT / "ZEUS_GROUNDED_QA_RECEIPT.json").write_text(
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
