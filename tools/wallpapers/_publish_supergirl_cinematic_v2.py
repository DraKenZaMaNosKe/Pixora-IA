"""Publica Supergirl V2 cinematografica y retira la revision anterior."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import get_json, put_json, IMG_BUCKET, SCENES_BUCKET


SID = "supergirl_crystal_hope_parallax_v2"
OLD_SID = "supergirl_crystal_hope_parallax"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/"
    r"wallpapers/1_por_editar/supergirl_crystal_hope_parallax_v2"
)


def main() -> None:
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    new_matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    old_matches = [item for item in catalog.get("items", []) if item.get("id") == OLD_SID]
    if len(new_matches) != 1 or len(old_matches) != 1:
        raise RuntimeError(
            f"Catalogo inesperado: nueva={len(new_matches)}, anterior={len(old_matches)}"
        )

    new_spec = get_json(SCENES_BUCKET, f"{SID}.json")
    old_spec = get_json(SCENES_BUCKET, f"{OLD_SID}.json")
    keys = {layer.get("key") for layer in new_spec.get("image_layers", [])}
    required = {
        "background", "shards_far", "shards_mid", "shards_near",
        "krypton_light_rays", "supergirl", "hair_wind_glint",
        "cape_wind_glint", "emblem_glow_0", "emblem_glow_1",
        "emblem_glow_2", "emblem_glow_3", "energy_wave_0",
        "energy_wave_1", "energy_wave_2",
    }
    if len(new_spec.get("image_layers", [])) != 15 or keys != required:
        raise RuntimeError("Inventario inesperado de capas en la V2")
    if len(new_spec.get("cycles", [])) != 2:
        raise RuntimeError("La V2 debe conservar sus dos ciclos cinematograficos")
    drift_keys = {
        layer.get("key") for layer in new_spec.get("image_layers", [])
        if layer.get("drift")
    }
    if not {"background", "shards_far", "shards_mid", "shards_near", "krypton_light_rays"}.issubset(drift_keys):
        raise RuntimeError("Faltan movimientos slow-motion en la V2")

    new_matches[0]["published"] = True
    old_matches[0]["published"] = False
    catalog["version"] = int(catalog.get("version", 0) or 0) + 1
    new_spec["published"] = True
    old_spec["published"] = False

    # Primero se escriben los objetos canónicos; después Postgres se actualiza
    # en una sola transacción para que solo una revisión quede pública.
    put_json(SCENES_BUCKET, f"{SID}.json", new_spec)
    put_json(SCENES_BUCKET, f"{OLD_SID}.json", old_spec)
    put_json(IMG_BUCKET, "catalog_index.json", catalog)

    conn = connect()
    cur = conn.cursor()
    cur.execute(
        "UPDATE wallpapers SET published = CASE WHEN id=%s THEN true ELSE false END "
        "WHERE id IN (%s,%s) RETURNING id,published",
        (SID, SID, OLD_SID),
    )
    rows = dict(cur.fetchall())
    if rows != {SID: True, OLD_SID: False}:
        conn.rollback()
        raise RuntimeError(f"Resultado inesperado de Postgres: {rows}")
    conn.commit()

    fcm = send_catalog_invalidate("wallpapers")
    receipt = {
        "scene_id": SID,
        "replaces_scene_id": OLD_SID,
        "published_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": catalog["version"],
        "catalog_published": {
            SID: bool(new_matches[0]["published"]),
            OLD_SID: bool(old_matches[0]["published"]),
        },
        "scene_spec_published": {
            SID: bool(new_spec["published"]),
            OLD_SID: bool(old_spec["published"]),
        },
        "postgres_published": rows,
        "fcm_catalog_invalidate": fcm,
        "qa_device": "HUAWEI VNS-L53",
        "image_layers": 15,
        "cycles": 2,
    }
    (ROOT / "SCENE_SPEC_PRODUCTION.json").write_text(
        json.dumps(new_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "PRODUCTION_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    cur.close()
    conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
