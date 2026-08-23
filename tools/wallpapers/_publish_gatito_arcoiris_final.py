"""Publica el gatito arcoiris V9 aprobado en Huawei."""
from __future__ import annotations

import hashlib
import json
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, get_json, put_json

SID = "gatito_arcoiris_ojos_live"
KEY = "gatito_arcoiris_rainbow_veins_cycle"
SPRITES_BUCKET = "wallpaper-sprites"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_arcoiris_psicodelico_20260822")
EXPECTED_VERSION = 283
FINAL_VERSION = 284
EXPECTED_ZIP_SIZE = 1_108_390
EXPECTED_ZIP_SHA256 = "ebb9efb5cf3c615c3062c6d9e06ca91c6b98bd008e62e237f1c1d3f6210ddd64"


def public_bytes(bucket: str, remote: str) -> bytes:
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}?nc={time.time_ns()}"
    with urllib.request.urlopen(url, timeout=45) as response:
        return response.read()


def validate_spec(spec: dict, published: bool) -> None:
    if spec.get("id") != SID or spec.get("published") is not published:
        raise RuntimeError("Estado del spec inesperado")
    layers = spec.get("image_layers", [])
    sprites = spec.get("sprites", [])
    if len(layers) != 1 or layers[0].get("key") != "background":
        raise RuntimeError("Inventario de capas cambio")
    if layers[0].get("revision") != 9 or abs(float(layers[0].get("scale", 0)) - 1.26) > .0001:
        raise RuntimeError("Revision o escala de fondo cambio")
    if len(sprites) != 1 or sprites[0].get("manifest_key") != KEY:
        raise RuntimeError("Sprite o manifest key cambio")
    sprite = sprites[0]
    params = sprite.get("params", {})
    expected = {"x": .5, "y": .5, "anchor_x": .5, "anchor_y": .5,
                "scale": .002333333, "fullscreen": False}
    for name, value in expected.items():
        actual = params.get(name)
        if isinstance(value, float):
            if abs(float(actual) - value) > 1e-8:
                raise RuntimeError(f"Parametro {name} cambio")
        elif actual is not value:
            raise RuntimeError(f"Parametro {name} cambio")
    if sprite.get("frame_skip") != 5:
        raise RuntimeError("Frame skip cambio")


def main() -> None:
    remote = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    manifest = get_json(SPRITES_BUCKET, "manifest.json")
    validate_spec(remote, False)
    if int(catalog.get("version", 0) or 0) != EXPECTED_VERSION:
        raise RuntimeError("Catalogo cambio")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if len(matches) != 1 or matches[0].get("published") is not False:
        raise RuntimeError("Entrada de catalogo inesperada")
    entry = manifest.get(KEY)
    if entry != {"zip": f"{KEY}.zip", "frames": 8, "size": EXPECTED_ZIP_SIZE}:
        raise RuntimeError("Manifest del sprite cambio")
    zip_bytes = public_bytes(SPRITES_BUCKET, f"{KEY}.zip")
    if len(zip_bytes) != EXPECTED_ZIP_SIZE or hashlib.sha256(zip_bytes).hexdigest() != EXPECTED_ZIP_SHA256:
        raise RuntimeError("ZIP remoto cambio")
    qa_files = [ROOT / "qa/HUAWEI_V9_QA_A.png", ROOT / "qa/HUAWEI_V9_QA_B.png"]
    if any(not path.is_file() or path.stat().st_size < 100_000 for path in qa_files):
        raise RuntimeError("Faltan capturas Huawei V9")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published,description,description_rich FROM wallpapers WHERE id=%s", (SID,))
    db_before = cur.fetchone()
    if not db_before or db_before[0] is not False:
        cur.close(); conn.close(); raise RuntimeError("Postgres no parte oculto")
    rich_local = (ROOT / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8")
    if matches[0].get("description") != db_before[1] or rich_local != db_before[2]:
        cur.close(); conn.close(); raise RuntimeError("Metadata no coincide")

    outputs = [ROOT / "SCENE_SPEC_PRODUCTION.json", ROOT / "PRODUCTION_RECEIPT.json"]
    output_before = {path: path.read_bytes() if path.exists() else None for path in outputs}
    spec_before = json.loads(json.dumps(remote)); catalog_before = json.loads(json.dumps(catalog))
    try:
        remote["published"] = True
        matches[0]["published"] = True
        catalog["version"] = FINAL_VERSION
        put_json(SCENES_BUCKET, f"{SID}.json", remote)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published", (SID,))
        if cur.fetchone() != (True,):
            raise RuntimeError("No se publico en Postgres")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM principal no confirmado")

        final_spec = get_json(SCENES_BUCKET, f"{SID}.json")
        final_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        final_manifest = get_json(SPRITES_BUCKET, "manifest.json")
        found = [item for item in final_catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published,description,description_rich FROM wallpapers WHERE id=%s", (SID,))
        final_db = cur.fetchone()
        expected_spec = json.loads(json.dumps(spec_before)); expected_spec["published"] = True
        expected_catalog = json.loads(json.dumps(catalog_before)); expected_catalog["version"] = FINAL_VERSION
        [item for item in expected_catalog["items"] if item.get("id") == SID][0]["published"] = True
        final_zip = public_bytes(SPRITES_BUCKET, f"{KEY}.zip")
        validate_spec(final_spec, True)
        if final_spec != expected_spec or final_catalog != expected_catalog or final_manifest != manifest:
            raise RuntimeError("Spec, catalogo o manifest cambio fuera de alcance")
        if len(found) != 1 or found[0].get("published") is not True or final_db != (True, db_before[1], db_before[2]):
            raise RuntimeError("Verificacion triple fallo")
        if hashlib.sha256(final_zip).hexdigest() != EXPECTED_ZIP_SHA256:
            raise RuntimeError("ZIP cambio durante publicacion")
        receipt = {"scene_id": SID, "published_at": datetime.now(timezone.utc).isoformat(),
                   "catalog_version": FINAL_VERSION, "scene_spec_published": True,
                   "catalog_published": True, "postgres_published": True,
                   "revision": 9, "qa_scope": "Huawei V9", "qa_captures": [p.name for p in qa_files],
                   "manifest_key": KEY, "frames": 8, "zip_size": EXPECTED_ZIP_SIZE,
                   "zip_sha256": EXPECTED_ZIP_SHA256, "fcm_catalog_invalidate": True}
        outputs[0].write_text(json.dumps(final_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except Exception as original_error:
        errors = []
        try: conn.rollback()
        except Exception as exc: errors.append(f"rollback DB: {exc}")
        try: put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        except Exception as exc: errors.append(f"spec: {exc}")
        try: put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        except Exception as exc: errors.append(f"catalogo: {exc}")
        try:
            cur.execute("UPDATE wallpapers SET published=false WHERE id=%s", (SID,)); conn.commit()
        except Exception as exc: errors.append(f"Postgres: {exc}")
        for path, previous in output_before.items():
            try:
                if previous is None: path.unlink(missing_ok=True)
                else: path.write_bytes(previous)
            except Exception as exc: errors.append(f"output {path.name}: {exc}")
        try:
            if get_json(SCENES_BUCKET, f"{SID}.json") != spec_before: errors.append("spec no restaurado")
        except Exception as exc: errors.append(f"verificacion spec: {exc}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before: errors.append("catalogo no restaurado")
        except Exception as exc: errors.append(f"verificacion catalogo: {exc}")
        try:
            cur.execute("SELECT published,description,description_rich FROM wallpapers WHERE id=%s", (SID,))
            if cur.fetchone() != db_before: errors.append("Postgres no restaurado")
        except Exception as exc: errors.append(f"verificacion DB: {exc}")
        try:
            if not send_catalog_invalidate("wallpapers"):
                print("ADVERTENCIA: FCM compensatorio no confirmado", file=sys.stderr)
        except Exception as exc: print(f"ADVERTENCIA: FCM compensatorio fallo: {exc}", file=sys.stderr)
        if errors: raise RuntimeError("Rollback incompleto: " + " | ".join(errors)) from original_error
        raise
    finally:
        cur.close(); conn.close()
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
