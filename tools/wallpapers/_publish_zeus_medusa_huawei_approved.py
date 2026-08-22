"""Publica Zeus y Medusa tras QA aprobado en Huawei, con rollback compensatorio."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


EXPECTED_CATALOG_VERSION = 251
PRODUCTION_CATALOG_VERSION = 252
SCENES = {
    "zeus_trono_tormenta": {
        "root": Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/zeus_trono_tormenta_20260820"),
        "qa": "qa/HUAWEI_QA_V3.png",
        "layers": {"background", "lightning_aura", "zeus"},
        "revision": 1,
        "paired": ("lightning_aura", "zeus"),
        "pair_pf": 0.18,
        "pair_bob": (1.2, 7.4),
        "pair_offset_y": 64,
    },
    "medusa_templo_petrificado": {
        "root": Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/medusa_templo_petrificado_20260820"),
        "qa": "qa/HUAWEI_QA.png",
        "layers": {"background", "emerald_gaze_aura", "medusa"},
        "revision": 1,
        "paired": ("emerald_gaze_aura", "medusa"),
        "pair_pf": 0.16,
        "pair_bob": (0.8, 7.0),
        "pair_offset_y": 0,
    },
}


def close_enough(actual: object, expected: float) -> bool:
    return abs(float(actual) - expected) <= 0.001


def validate_spec(sid: str, spec: dict, cfg: dict) -> None:
    if spec.get("id") != sid or spec.get("published") is not False:
        raise RuntimeError(f"{sid}: el spec no parte oculto")
    layers = spec.get("image_layers", [])
    if {layer.get("key") for layer in layers} != cfg["layers"]:
        raise RuntimeError(f"{sid}: inventario de capas inesperado")
    if any(int(layer.get("revision", 0)) != cfg["revision"] for layer in layers):
        raise RuntimeError(f"{sid}: revision visual inesperada")
    background = next(layer for layer in layers if layer.get("key") == "background")
    if not close_enough(background.get("scale", -1), 1.26) or not close_enough(background.get("parallax_factor", -1), 0.06):
        raise RuntimeError(f"{sid}: fondo aprobado cambio")
    first = next(layer for layer in layers if layer.get("key") == cfg["paired"][0])
    second = next(layer for layer in layers if layer.get("key") == cfg["paired"][1])
    for layer in (first, second):
        if not close_enough(layer.get("parallax_factor", -1), cfg["pair_pf"]):
            raise RuntimeError(f"{sid}: paralaje sincronizado cambio")
        if not close_enough(layer.get("bob_amplitude_px", -1), cfg["pair_bob"][0]):
            raise RuntimeError(f"{sid}: amplitud bob cambio")
        if not close_enough(layer.get("bob_period_sec", -1), cfg["pair_bob"][1]):
            raise RuntimeError(f"{sid}: periodo bob cambio")
        if int(layer.get("offset_y_px", -999)) != cfg["pair_offset_y"]:
            raise RuntimeError(f"{sid}: apoyo vertical aprobado cambio")
    qa = cfg["root"] / cfg["qa"]
    if not qa.is_file() or qa.stat().st_size < 100_000:
        raise RuntimeError(f"{sid}: falta captura QA Huawei")


def main() -> None:
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    if int(catalog.get("version", 0) or 0) != EXPECTED_CATALOG_VERSION:
        raise RuntimeError("La version inicial del catalogo cambio")

    specs: dict[str, dict] = {}
    matches: dict[str, dict] = {}
    for sid, cfg in SCENES.items():
        spec = get_json(SCENES_BUCKET, f"{sid}.json")
        validate_spec(sid, spec, cfg)
        found = [item for item in catalog.get("items", []) if item.get("id") == sid]
        if len(found) != 1 or found[0].get("published") is not False:
            raise RuntimeError(f"{sid}: catalogo no parte oculto o esta duplicado")
        specs[sid] = spec
        matches[sid] = found[0]

    conn = connect()
    cur = conn.cursor()
    db_before: dict[str, bool] = {}
    for sid in SCENES:
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (sid,))
        row = cur.fetchone()
        if not row or bool(row[0]) is not False:
            cur.close()
            conn.close()
            raise RuntimeError(f"{sid}: Postgres no parte oculto")
        db_before[sid] = bool(row[0])

    output_paths = [
        cfg["root"] / filename
        for cfg in SCENES.values()
        for filename in ("SCENE_SPEC_PRODUCTION.json", "PRODUCTION_RECEIPT.json")
    ]
    output_before = {
        path: path.read_bytes() if path.exists() else None
        for path in output_paths
    }
    specs_before = json.loads(json.dumps(specs))
    catalog_before = json.loads(json.dumps(catalog))
    try:
        for sid, spec in specs.items():
            spec["published"] = True
            matches[sid]["published"] = True
            put_json(SCENES_BUCKET, f"{sid}.json", spec)
        catalog["version"] = PRODUCTION_CATALOG_VERSION
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        for sid in SCENES:
            cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published", (sid,))
            row = cur.fetchone()
            if not row or not bool(row[0]):
                raise RuntimeError(f"{sid}: no se pudo publicar en Postgres")
        conn.commit()
        fcm = send_catalog_invalidate("wallpapers")
        if not fcm:
            raise RuntimeError("No se pudo invalidar el catalogo en los dispositivos")

        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        if int(remote_catalog.get("version", 0) or 0) != PRODUCTION_CATALOG_VERSION:
            raise RuntimeError("La version final del catalogo no coincide")
        receipts = {}
        for sid, cfg in SCENES.items():
            remote_spec = get_json(SCENES_BUCKET, f"{sid}.json")
            remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == sid]
            cur.execute("SELECT published FROM wallpapers WHERE id=%s", (sid,))
            db_after = cur.fetchone()
            if (
                remote_spec.get("published") is not True
                or len(remote_matches) != 1
                or remote_matches[0].get("published") is not True
                or not db_after
                or bool(db_after[0]) is not True
            ):
                raise RuntimeError(f"{sid}: fallo la verificacion triple final")
            validate_copy = json.loads(json.dumps(remote_spec))
            validate_copy["published"] = False
            validate_spec(sid, validate_copy, cfg)
            receipt = {
                "scene_id": sid,
                "published_at": datetime.now(timezone.utc).isoformat(),
                "catalog_version": PRODUCTION_CATALOG_VERSION,
                "scene_spec_published": True,
                "catalog_published": True,
                "postgres_published": True,
                "revision": cfg["revision"],
                "qa_scope": "Huawei only, per user instruction",
                "qa_device": "HUAWEI VNS-L53",
                "qa_capture": cfg["qa"],
                "fcm_catalog_invalidate": True,
            }
            (cfg["root"] / "SCENE_SPEC_PRODUCTION.json").write_text(
                json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            (cfg["root"] / "PRODUCTION_RECEIPT.json").write_text(
                json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            receipts[sid] = receipt
    except Exception:
        conn.rollback()
        for sid, previous in specs_before.items():
            put_json(SCENES_BUCKET, f"{sid}.json", previous)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        for sid, previous in db_before.items():
            cur.execute("UPDATE wallpapers SET published=%s WHERE id=%s", (previous, sid))
        conn.commit()
        for path, previous in output_before.items():
            if previous is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(previous)
        cur.close()
        conn.close()
        raise

    cur.close()
    conn.close()
    print(json.dumps(receipts, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
