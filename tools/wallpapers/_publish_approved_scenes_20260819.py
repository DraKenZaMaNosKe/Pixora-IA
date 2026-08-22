"""Publica tres escenas aprobadas en Huawei y Samsung, con rollback conjunto."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


SCENES = {
    "picaro_puerta_roja": {
        "root": Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/picaro_puerta_roja_20260818"),
        "revision": 2,
        "layers": {"background", "foreground_door"},
        "qa": ["qa/HUAWEI_QA_V2.png", "qa/SAMSUNG_QA.png"],
    },
    "atenea_estratega_luna": {
        "root": Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/atenea_estratega_luna_20260819"),
        "revision": 1,
        "layers": {"background", "atenea"},
        "qa": ["qa/HUAWEI_QA.png", "qa/SAMSUNG_QA.png"],
    },
    "hades_cerbero_umbral": {
        "root": Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/hades_cerbero_umbral_20260819"),
        "revision": 1,
        "layers": {"background", "hades", "cerberus"},
        "qa": ["qa/HUAWEI_QA.png", "qa/SAMSUNG_QA.png"],
    },
}


def clone(value):
    return json.loads(json.dumps(value))


def main() -> None:
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    catalog_before = clone(catalog)
    specs = {}
    specs_before = {}
    entries = {}

    for sid, cfg in SCENES.items():
        spec = get_json(SCENES_BUCKET, f"{sid}.json")
        matches = [item for item in catalog.get("items", []) if item.get("id") == sid]
        if len(matches) != 1:
            raise RuntimeError(f"{sid}: se esperaba una entrada unica de catalogo")
        if spec.get("published") is not False or matches[0].get("published") is not False:
            raise RuntimeError(f"{sid}: no parte del estado oculto esperado")
        layers = spec.get("image_layers", [])
        keys = {layer.get("key") for layer in layers}
        if keys != cfg["layers"]:
            raise RuntimeError(f"{sid}: inventario de capas inesperado: {keys}")
        if any(int(layer.get("revision", 0)) != cfg["revision"] for layer in layers):
            raise RuntimeError(f"{sid}: revision aprobada cambio")
        background = next(layer for layer in layers if layer.get("key") == "background")
        if abs(float(background.get("scale", 0)) - 1.26) > 0.001:
            raise RuntimeError(f"{sid}: cobertura de fondo aprobada cambio")
        for relative in cfg["qa"]:
            capture = cfg["root"] / relative
            if not capture.is_file() or capture.stat().st_size < 100_000:
                raise RuntimeError(f"{sid}: falta evidencia QA {relative}")
        specs[sid] = spec
        specs_before[sid] = clone(spec)
        entries[sid] = matches[0]

    conn = connect()
    cur = conn.cursor()
    db_before = {}
    for sid in SCENES:
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (sid,))
        row = cur.fetchone()
        if not row or bool(row[0]) is not False:
            raise RuntimeError(f"{sid}: Postgres no parte del estado oculto esperado")
        db_before[sid] = bool(row[0])

    try:
        for sid in SCENES:
            specs[sid]["published"] = True
            entries[sid]["published"] = True
            put_json(SCENES_BUCKET, f"{sid}.json", specs[sid])
        catalog["version"] = int(catalog.get("version", 0) or 0) + 1
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        for sid in SCENES:
            cur.execute(
                "UPDATE wallpapers SET published=true WHERE id=%s RETURNING published",
                (sid,),
            )
            row = cur.fetchone()
            if not row or not bool(row[0]):
                raise RuntimeError(f"{sid}: fallo al publicar en Postgres")
        conn.commit()
        fcm = send_catalog_invalidate("wallpapers")
    except Exception:
        conn.rollback()
        for sid, old_spec in specs_before.items():
            put_json(SCENES_BUCKET, f"{sid}.json", old_spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        for sid, old_value in db_before.items():
            cur.execute("UPDATE wallpapers SET published=%s WHERE id=%s", (old_value, sid))
        conn.commit()
        cur.close()
        conn.close()
        raise

    remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    receipt_common = {
        "published_at": datetime.now(timezone.utc).isoformat(),
        "catalog_version": remote_catalog.get("version"),
        "qa_devices": ["HUAWEI VNS-L53", "Samsung SM-A155M"],
        "fcm_catalog_invalidate": fcm,
    }
    output = []
    for sid, cfg in SCENES.items():
        remote_spec = get_json(SCENES_BUCKET, f"{sid}.json")
        remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == sid]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (sid,))
        db_row = cur.fetchone()
        if not remote_spec.get("published") or len(remote_matches) != 1 or not remote_matches[0].get("published") or not db_row or not db_row[0]:
            raise RuntimeError(f"{sid}: fallo la verificacion remota final")
        receipt = {
            **receipt_common,
            "scene_id": sid,
            "scene_spec_published": True,
            "catalog_published": True,
            "postgres_published": True,
            "revision": cfg["revision"],
            "background_scale": 1.26,
            "qa_captures": cfg["qa"],
        }
        (cfg["root"] / "SCENE_SPEC_PRODUCTION.json").write_text(
            json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (cfg["root"] / "PRODUCTION_RECEIPT.json").write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        output.append(receipt)

    cur.close()
    conn.close()
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
