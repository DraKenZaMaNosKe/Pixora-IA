"""Publica el Santuario 2.5D tras QA aprobado en Huawei y Samsung."""
from __future__ import annotations

import json
import sys
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json

SID = "santuario_abisal_depth_2_5d"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/santuario_abisal_depth_2_5d_20260823")
CATALOG_BEFORE, CATALOG_AFTER = 286, 287
QA_FILES = [ROOT / "qa/HUAWEI_FACE_V2_QA.png", ROOT / "qa/SAMSUNG_FACE_V2_QA.png"]


def validate(spec: dict, published: bool) -> None:
    if spec.get("id") != SID or spec.get("published") is not published:
        raise RuntimeError("Estado del spec inesperado")
    layers = spec.get("image_layers", [])
    if len(layers) != 1 or layers[0].get("key") != "background":
        raise RuntimeError("Inventario inesperado")
    layer = layers[0]
    if int(layer.get("revision", 0)) != 2:
        raise RuntimeError("Revision aprobada cambio")
    if abs(float(layer.get("scale", 0)) - 1.26) > .001:
        raise RuntimeError("Escala aprobada cambio")
    if abs(float(layer.get("depth_strength", 0)) - .50) > .001:
        raise RuntimeError("Profundidad aprobada cambio")
    if not str(layer.get("depth_map_url", "")).endswith(f"{SID}_background_depth.webp"):
        raise RuntimeError("Mapa de profundidad inesperado")


def main() -> None:
    approved = json.loads((ROOT / "SCENE_SPEC_QA_FACE_V2.json").read_text(encoding="utf-8"))
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    validate(spec, False)
    if spec != approved:
        raise RuntimeError("Spec remoto distinto del QA")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [x for x in catalog.get("items", []) if x.get("id") == SID]
    if catalog.get("version") != CATALOG_BEFORE or len(matches) != 1 or matches[0].get("published") is not False:
        raise RuntimeError("Catalogo inicial inesperado")
    if any(not p.is_file() or p.stat().st_size < 100_000 for p in QA_FILES):
        raise RuntimeError("Falta evidencia QA de ambos dispositivos")

    spec_before, catalog_before = deepcopy(spec), deepcopy(catalog)
    outputs = [ROOT / "SCENE_SPEC_PRODUCTION.json", ROOT / "PRODUCTION_RECEIPT.json"]
    output_before = {p: p.read_bytes() if p.exists() else None for p in outputs}
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() != (False,):
        cur.close(); conn.close(); raise RuntimeError("Postgres no parte hidden")
    try:
        spec["published"] = True
        matches[0]["published"] = True
        catalog["version"] = CATALOG_AFTER
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published", (SID,))
        if cur.fetchone() != (True,):
            raise RuntimeError("No se publico en Postgres")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM no confirmado")

        remote = get_json(SCENES_BUCKET, f"{SID}.json")
        expected = deepcopy(approved); expected["published"] = True
        validate(remote, True)
        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        remote_matches = [x for x in remote_catalog.get("items", []) if x.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        if remote != expected or remote_catalog != catalog or len(remote_matches) != 1 or remote_matches[0].get("published") is not True or cur.fetchone() != (True,):
            raise RuntimeError("Verificacion triple final fallo")

        receipt = {
            "scene_id": SID,
            "published_at": datetime.now(timezone.utc).isoformat(),
            "catalog_version": CATALOG_AFTER,
            "triple_published": True,
            "revision": 2,
            "depth_strength": .50,
            "qa_devices": ["HUAWEI VNS-L53", "Samsung SM-A155M"],
            "qa_captures": ["qa/HUAWEI_FACE_V2_QA.png", "qa/SAMSUNG_FACE_V2_QA.png"],
            "fcm_catalog_invalidate": True,
        }
        outputs[0].write_text(json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original:
        errors: list[str] = []
        try: conn.rollback()
        except Exception as exc: errors.append(f"db rollback: {exc}")
        for label, bucket, name, value in (
            ("spec", SCENES_BUCKET, f"{SID}.json", spec_before),
            ("catalog", IMG_BUCKET, "catalog_index.json", catalog_before),
        ):
            try: put_json(bucket, name, value)
            except Exception as exc: errors.append(f"{label}: {exc}")
        try:
            cur.execute("UPDATE wallpapers SET published=false WHERE id=%s", (SID,)); conn.commit()
        except Exception as exc: errors.append(f"db restore: {exc}")
        for path, previous in output_before.items():
            try: path.unlink(missing_ok=True) if previous is None else path.write_bytes(previous)
            except Exception as exc: errors.append(f"output {path.name}: {exc}")
        try:
            if get_json(SCENES_BUCKET, f"{SID}.json") != spec_before: errors.append("spec no restaurado")
        except Exception as exc: errors.append(f"verify spec: {exc}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before: errors.append("catalogo no restaurado")
        except Exception as exc: errors.append(f"verify catalog: {exc}")
        try:
            cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
            if cur.fetchone() != (False,): errors.append("db no restaurada")
        except Exception as exc: errors.append(f"verify db: {exc}")
        for path, previous in output_before.items():
            try:
                current = path.read_bytes() if path.exists() else None
                if current != previous: errors.append(f"output no restaurado: {path.name}")
            except Exception as exc: errors.append(f"verify output {path.name}: {exc}")
        try:
            if not send_catalog_invalidate("wallpapers"): errors.append("FCM compensatorio false")
        except Exception as exc: errors.append(f"FCM compensatorio: {exc}")
        if errors: raise RuntimeError("Rollback incompleto: " + " | ".join(errors)) from original
        raise
    finally:
        cur.close(); conn.close()


if __name__ == "__main__":
    main()
