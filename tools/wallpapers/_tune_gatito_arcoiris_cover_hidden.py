"""Amplia el fondo del gatito arcoiris oculto para cubrir Huawei sin franjas."""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json

SID = "gatito_arcoiris_ojos_live"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_arcoiris_psicodelico_20260822")


def main() -> None:
    spec_before = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog_before = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog_before.get("items", []) if item.get("id") == SID]
    if spec_before.get("published") is not False or len(matches) != 1 or matches[0].get("published") is not False:
        raise RuntimeError("La escena no esta oculta de forma unica")
    layers = spec_before.get("image_layers") or []
    if len(layers) != 1 or layers[0].get("key") != "background" or float(layers[0].get("scale", 0)) != 1.0:
        raise RuntimeError("Geometria inicial inesperada")
    sprites = spec_before.get("sprites") or []
    if len(sprites) != 1 or sprites[0].get("params", {}).get("fullscreen") is not True:
        raise RuntimeError("Overlay inicial inesperado")
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() != (False,):
        cur.close(); conn.close(); raise RuntimeError("Postgres no esta hidden")
    output = ROOT / "SCENE_SPEC_QA.json"
    output_before = output.read_bytes() if output.exists() else None
    try:
        spec = copy.deepcopy(spec_before)
        spec["image_layers"][0]["scale"] = 1.26
        spec["image_layers"][0]["revision"] = int(spec["image_layers"][0].get("revision", 1)) + 1
        spec["sprites"][0]["params"].update({
            "fullscreen": False,
            "x": 0.5,
            "y": 0.5,
            "anchor_x": 0.5,
            "anchor_y": 0.5,
            "scale": 0.002333333,
        })
        catalog = copy.deepcopy(catalog_before)
        catalog["version"] = int(catalog.get("version", 0)) + 1
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        remote = get_json(SCENES_BUCKET, f"{SID}.json")
        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,)); db = cur.fetchone()
        if remote != spec or remote_catalog != catalog or db != (False,):
            raise RuntimeError("Verificacion remota fallo")
        output.write_text(json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM no confirmado")
        print(json.dumps({"scene_id": SID, "published": False, "background_scale": 1.26, "catalog_version": catalog["version"]}, indent=2))
    except Exception as original_error:
        errors = []
        try: put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        except Exception as exc: errors.append(f"spec: {exc}")
        try: put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        except Exception as exc: errors.append(f"catalogo: {exc}")
        try:
            if output_before is None: output.unlink(missing_ok=True)
            else: output.write_bytes(output_before)
        except Exception as exc: errors.append(f"output: {exc}")
        try:
            if get_json(SCENES_BUCKET, f"{SID}.json") != spec_before: errors.append("spec no restaurado")
        except Exception as exc: errors.append(f"verificacion spec: {exc}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before: errors.append("catalogo no restaurado")
        except Exception as exc: errors.append(f"verificacion catalogo: {exc}")
        try:
            current = output.read_bytes() if output.exists() else None
            if current != output_before: errors.append("output no restaurado")
        except Exception as exc: errors.append(f"verificacion output: {exc}")
        try:
            if not send_catalog_invalidate("wallpapers"):
                print("ADVERTENCIA: FCM compensatorio no confirmado", file=sys.stderr)
        except Exception as exc: print(f"ADVERTENCIA FCM: {exc}", file=sys.stderr)
        if errors: raise RuntimeError("Rollback incompleto: " + " | ".join(errors)) from original_error
        raise
    finally:
        cur.close(); conn.close()


if __name__ == "__main__":
    main()
