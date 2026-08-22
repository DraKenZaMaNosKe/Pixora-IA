"""Publica la composición V5 aprobada de Pícaro tras QA en Huawei y Samsung."""
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
QA = ["qa/HUAWEI_GROUNDED_QA_V5.png", "qa/SAMSUNG_GROUNDED_QA_V5.png"]
EXPECTED = {"x": 0.55, "y": 0.75, "z": 30, "parallax_factor": 0.07}


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    if int(catalog.get("version", 0) or 0) != 246:
        raise RuntimeError("La versión inicial del catálogo cambió")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1 or spec.get("published") is not False or matches[0].get("published") is not False:
        raise RuntimeError("Pícaro no parte del estado oculto aprobado")
    if len(spec.get("sprites", [])) != 1:
        raise RuntimeError("Inventario de sprites inesperado")
    sprite = spec["sprites"][0]
    params = sprite.get("params", {})
    if sprite.get("manifest_key") != "picaro_puerta_roja_blink":
        raise RuntimeError("Manifest inesperado")
    for key, value in EXPECTED.items():
        if abs(float(params.get(key, -999)) - value) > 0.001:
            raise RuntimeError(f"El parámetro aprobado {key} cambió")
    layers = spec.get("image_layers", [])
    if {layer.get("key") for layer in layers} != {"background", "foreground_door"}:
        raise RuntimeError("Capas inesperadas")
    if any(int(layer.get("revision", 0)) != 2 for layer in layers):
        raise RuntimeError("Revisión visual inesperada")
    door = next(layer for layer in layers if layer.get("key") == "foreground_door")
    if int(door.get("z", -1)) != 20 or abs(float(door.get("parallax_factor", -1)) - 0.07) > 0.001:
        raise RuntimeError("La geometría aprobada de la puerta cambió")
    if any(not (ROOT / rel).is_file() or (ROOT / rel).stat().st_size < 100_000 for rel in QA):
        raise RuntimeError("Falta evidencia QA V5")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    db_before = cur.fetchone()
    if not db_before or bool(db_before[0]) is not False:
        raise RuntimeError("Postgres no está oculto")
    spec_before = json.loads(json.dumps(spec))
    catalog_before = json.loads(json.dumps(catalog))
    try:
        spec["published"] = True
        matches[0]["published"] = True
        catalog["version"] = 247
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published", (SID,))
        row = cur.fetchone()
        if not row or not bool(row[0]):
            raise RuntimeError("No se pudo publicar en Postgres")
        conn.commit()
        fcm = send_catalog_invalidate("wallpapers")

        remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        db_after = cur.fetchone()
        if (
            not remote_spec.get("published")
            or int(remote_catalog.get("version", 0) or 0) != 247
            or len(remote_matches) != 1
            or not remote_matches[0].get("published")
            or not db_after
            or not bool(db_after[0])
        ):
            raise RuntimeError("Falló la verificación remota final")
        receipt = {
            "scene_id": SID,
            "published_at": datetime.now(timezone.utc).isoformat(),
            "catalog_version": 247,
            "scene_spec_published": True,
            "catalog_published": True,
            "postgres_published": True,
            "sprite_params": EXPECTED,
            "revision": 2,
            "qa_devices": ["HUAWEI VNS-L53", "Samsung SM-A155M"],
            "qa_captures": QA,
            "fcm_catalog_invalidate": fcm,
        }
        (ROOT / "SCENE_SPEC_PRODUCTION_V5.json").write_text(
            json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (ROOT / "PRODUCTION_RECEIPT_V5.json").write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except Exception:
        conn.rollback()
        put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        cur.execute("UPDATE wallpapers SET published=%s WHERE id=%s", (bool(db_before[0]), SID))
        conn.commit()
        cur.close()
        conn.close()
        raise

    cur.close()
    conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
