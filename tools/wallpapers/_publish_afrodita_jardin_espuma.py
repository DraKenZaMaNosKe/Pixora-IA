"""Publica Afrodita tras QA aprobado en Huawei."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


SID = "afrodita_jardin_espuma"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/afrodita_jardin_espuma_20260820")
QA = ROOT / "qa/HUAWEI_QA.png"
CATALOG_BEFORE = 257
CATALOG_AFTER = 258


def close(actual: object, expected: float) -> bool:
    return abs(float(actual) - expected) <= 0.001


def validate(spec: dict, hidden: bool) -> None:
    if spec.get("id") != SID or bool(spec.get("published")) is not (not hidden):
        raise RuntimeError("Estado del spec inesperado")
    layers = spec.get("image_layers", [])
    if {layer.get("key") for layer in layers} != {"background", "pearl_aura", "aphrodite_and_dove"}:
        raise RuntimeError("Inventario de capas inesperado")
    if any(int(layer.get("revision", 0)) != 1 for layer in layers):
        raise RuntimeError("Revision visual inesperada")
    bg = next(layer for layer in layers if layer.get("key") == "background")
    if not close(bg.get("scale", -1), 1.26) or not close(bg.get("parallax_factor", -1), .06):
        raise RuntimeError("Fondo aprobado cambio")
    for key in ("pearl_aura", "aphrodite_and_dove"):
        layer = next(layer for layer in layers if layer.get("key") == key)
        if not close(layer.get("scale", -1), 1.0) or not close(layer.get("parallax_factor", -1), .14):
            raise RuntimeError("Paralaje sincronizado cambio")
        if not close(layer.get("bob_amplitude_px", -1), .6) or not close(layer.get("bob_period_sec", -1), 8.0):
            raise RuntimeError("Bob sincronizado cambio")


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    validate(spec, hidden=True)
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    if int(catalog.get("version", 0) or 0) != CATALOG_BEFORE:
        raise RuntimeError("Version inicial del catalogo cambio")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1 or matches[0].get("published") is not False:
        raise RuntimeError("Afrodita no parte oculta o esta duplicada")
    if not QA.is_file() or QA.stat().st_size < 100_000:
        raise RuntimeError("Falta captura QA Huawei")

    outputs = [ROOT / "SCENE_SPEC_PRODUCTION.json", ROOT / "PRODUCTION_RECEIPT.json"]
    outputs_before = {path: path.read_bytes() if path.exists() else None for path in outputs}
    spec_before = json.loads(json.dumps(spec))
    catalog_before = json.loads(json.dumps(catalog))
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    row = cur.fetchone()
    if not row or bool(row[0]) is not False:
        cur.close(); conn.close()
        raise RuntimeError("Postgres no parte oculto")
    db_before = bool(row[0])
    try:
        spec["published"] = True
        matches[0]["published"] = True
        catalog["version"] = CATALOG_AFTER
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published", (SID,))
        updated = cur.fetchone()
        if not updated or not bool(updated[0]):
            raise RuntimeError("No se pudo publicar en Postgres")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("No se pudo invalidar el catalogo")

        remote = get_json(SCENES_BUCKET, f"{SID}.json")
        validate(remote, hidden=False)
        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        remote_matches = [item for item in remote_catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        db_after = cur.fetchone()
        if int(remote_catalog.get("version", 0) or 0) != CATALOG_AFTER or len(remote_matches) != 1 or remote_matches[0].get("published") is not True or not db_after or bool(db_after[0]) is not True:
            raise RuntimeError("Fallo la verificacion triple final")
        receipt = {
            "scene_id": SID,
            "published_at": datetime.now(timezone.utc).isoformat(),
            "catalog_version": CATALOG_AFTER,
            "scene_spec_published": True,
            "catalog_published": True,
            "postgres_published": True,
            "revision": 1,
            "qa_scope": "Huawei only, per user instruction",
            "qa_capture": "qa/HUAWEI_QA.png",
            "fcm_catalog_invalidate": True,
        }
        outputs[0].write_text(json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except Exception:
        original_error = sys.exc_info()[1]
        conn.rollback()
        put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        cur.execute("UPDATE wallpapers SET published=%s WHERE id=%s", (db_before, SID))
        conn.commit()
        for path, previous in outputs_before.items():
            if previous is None:
                if path.exists(): path.unlink()
            else:
                path.write_bytes(previous)
        # Verifica la restauracion y avisa a los dispositivos que descarten
        # cualquier catalogo transitorio recibido antes del fallo.
        restored_spec = get_json(SCENES_BUCKET, f"{SID}.json")
        restored_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        restored_matches = [item for item in restored_catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        restored_db = cur.fetchone()
        if (
            restored_spec.get("published") is not False
            or int(restored_catalog.get("version", 0) or 0) != CATALOG_BEFORE
            or len(restored_matches) != 1
            or restored_matches[0].get("published") is not False
            or not restored_db
            or bool(restored_db[0]) is not False
        ):
            raise RuntimeError("Fallo la verificacion del rollback") from original_error
        try:
            send_catalog_invalidate("wallpapers")
        except Exception:
            pass
        cur.close(); conn.close()
        raise
    cur.close(); conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

