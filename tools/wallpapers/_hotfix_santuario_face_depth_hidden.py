"""Reemplaza rostro/master y suaviza depth del Santuario, siempre oculto."""
from __future__ import annotations

import io
import json
import sys
import urllib.request
from copy import deepcopy
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, PROJECT, SK, get_json, put, put_json

SID = "santuario_abisal_depth_2_5d"
EXPECTED_CATALOG = 285
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/santuario_abisal_depth_2_5d_20260823")
PROD = ROOT / "production"
ASSETS = {
    f"{SID}.webp": PROD / "santuario_abisal_1080x2340.png",
    f"{SID}_preview.webp": PROD / "santuario_abisal_1080x2340.png",
    f"{SID}_background.webp": PROD / "santuario_abisal_1080x2340.png",
    f"{SID}_background_depth.webp": PROD / "santuario_abisal_depth_1080x2340.png",
}


def public_bytes(remote: str) -> bytes:
    import time
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{remote}?nc={time.time_ns()}"
    )
    req.add_header("Cache-Control", "no-cache")
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read()


def webp(path: Path, *, lossless: bool = False) -> bytes:
    with Image.open(path) as image:
        mode = "L" if lossless else "RGB"
        image = image.convert(mode)
        if image.size != (1080, 2340):
            raise RuntimeError(f"Dimension inesperada {path.name}: {image.size}")
        out = io.BytesIO()
        image.save(out, "WEBP", lossless=lossless, quality=90, method=6)
        return out.getvalue()


def main() -> None:
    catalog_before = get_json(IMG_BUCKET, "catalog_index.json")
    spec_before = get_json(SCENES_BUCKET, f"{SID}.json")
    matches = [x for x in catalog_before.get("items", []) if x.get("id") == SID]
    layer = spec_before.get("image_layers", [{}])[0]
    if catalog_before.get("version") != EXPECTED_CATALOG or len(matches) != 1:
        raise RuntimeError("Catalogo inicial inesperado")
    if spec_before.get("published") is not False or matches[0].get("published") is not False:
        raise RuntimeError("La escena debe permanecer oculta")
    if len(spec_before.get("image_layers", [])) != 1 or layer.get("key") != "background":
        raise RuntimeError("Inventario de capas inesperado")
    if layer.get("revision") != 1 or abs(float(layer.get("scale", 0)) - 1.26) > .001:
        raise RuntimeError("Revision o escala inicial inesperada")

    bodies = {
        name: webp(path, lossless=name.endswith("_depth.webp"))
        for name, path in ASSETS.items()
    }
    old_assets = {name: public_bytes(name) for name in ASSETS}
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() != (False,):
        cur.close(); conn.close()
        raise RuntimeError("Postgres no esta oculto")

    outputs = [ROOT / "SCENE_SPEC_QA_FACE_V2.json", ROOT / "HOTFIX_FACE_V2_RECEIPT.json"]
    backups = {p: p.read_bytes() if p.exists() else None for p in outputs}
    try:
        for name, body in bodies.items():
            put(IMG_BUCKET, name, body)

        spec_after = deepcopy(spec_before)
        spec_after["published"] = False
        spec_after["image_layers"][0]["revision"] = 2
        spec_after["image_layers"][0]["depth_strength"] = 0.50
        put_json(SCENES_BUCKET, f"{SID}.json", spec_after)

        catalog_after = deepcopy(catalog_before)
        catalog_after["version"] = EXPECTED_CATALOG + 1
        put_json(IMG_BUCKET, "catalog_index.json", catalog_after)

        remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        if remote_spec != spec_after or remote_catalog != catalog_after or cur.fetchone() != (False,):
            raise RuntimeError("Verificacion hidden del hotfix fallo")
        for name, body in bodies.items():
            if public_bytes(name) != body:
                raise RuntimeError(f"Asset remoto distinto: {name}")

        outputs[0].write_text(json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        receipt = {
            "scene_id": SID,
            "published": False,
            "catalog_version": EXPECTED_CATALOG + 1,
            "background_revision": 2,
            "depth_strength": 0.50,
            "face_corrected": True,
            "face_depth_rigidified": True,
        }
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM no confirmado")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original:
        errors: list[str] = []
        for name, body in old_assets.items():
            try: put(IMG_BUCKET, name, body)
            except Exception as exc: errors.append(f"asset {name}: {exc}")
        for label, bucket, name, value in (
            ("spec", SCENES_BUCKET, f"{SID}.json", spec_before),
            ("catalog", IMG_BUCKET, "catalog_index.json", catalog_before),
        ):
            try: put_json(bucket, name, value)
            except Exception as exc: errors.append(f"{label}: {exc}")
        for path, previous in backups.items():
            try:
                path.unlink(missing_ok=True) if previous is None else path.write_bytes(previous)
            except Exception as exc: errors.append(f"output {path.name}: {exc}")
        for name, body in old_assets.items():
            try:
                if public_bytes(name) != body:
                    errors.append(f"asset no restaurado: {name}")
            except Exception as exc: errors.append(f"verificacion asset {name}: {exc}")
        try:
            if get_json(SCENES_BUCKET, f"{SID}.json") != spec_before:
                errors.append("spec no restaurado")
        except Exception as exc: errors.append(f"verificacion spec: {exc}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before:
                errors.append("catalogo no restaurado")
        except Exception as exc: errors.append(f"verificacion catalogo: {exc}")
        try:
            cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
            if cur.fetchone() != (False,):
                errors.append("Postgres no permanecio hidden")
        except Exception as exc: errors.append(f"verificacion Postgres: {exc}")
        for path, previous in backups.items():
            try:
                current = path.read_bytes() if path.exists() else None
                if current != previous:
                    errors.append(f"output no restaurado: {path.name}")
            except Exception as exc: errors.append(f"verificacion output {path.name}: {exc}")
        try:
            if not send_catalog_invalidate("wallpapers"):
                errors.append("FCM compensatorio false")
        except Exception as exc: errors.append(f"FCM compensatorio: {exc}")
        if errors:
            raise RuntimeError("Rollback incompleto: " + " | ".join(errors)) from original
        raise
    finally:
        cur.close(); conn.close()


if __name__ == "__main__":
    main()
