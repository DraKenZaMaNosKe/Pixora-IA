"""Carga oculta del gatito arcoiris animado para QA en Huawei."""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from _fcm_push import send_catalog_invalidate
from apply_migration import connect
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, SK, get_json, put_json, upload_scene
from sprite_pack_utils import (
    MANIFEST_KEY as MANIFEST_OBJECT,
    SPRITES_BUCKET,
    fetch_sprite_manifest,
    load_service_key,
    put_sprite_manifest,
    upload_sprite_pack,
)


SID = "gatito_arcoiris_ojos_live"
MANIFEST_KEY = "gatito_arcoiris_rainbow_veins_cycle"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"gatito_arcoiris_psicodelico_20260822"
)
ZIP_PATH = ROOT / "live" / "sprites" / "rainbow_veins_cycle.zip"
OBJECTS = [
    (SCENES_BUCKET, f"{SID}.json"),
    (IMG_BUCKET, f"{SID}.webp"),
    (IMG_BUCKET, f"{SID}_preview.webp"),
    (IMG_BUCKET, f"{SID}_background.webp"),
    (SPRITES_BUCKET, f"{MANIFEST_KEY}.zip"),
]


def is_missing(exc: urllib.error.HTTPError) -> bool:
    try:
        payload = json.loads(exc.read().decode("utf-8", "replace"))
    except json.JSONDecodeError:
        return False
    return (
        exc.code in {400, 404}
        and str(payload.get("statusCode")) == "404"
        and payload.get("code") == "NoSuchKey"
    )


def delete_object(bucket: str, remote: str) -> None:
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}", method="DELETE"
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("apikey", SK)
    try:
        with urllib.request.urlopen(req, timeout=30):
            pass
    except urllib.error.HTTPError as exc:
        if not is_missing(exc):
            raise


def validate_zip() -> None:
    with zipfile.ZipFile(ZIP_PATH, "r") as zf:
        if zf.testzip() is not None:
            raise RuntimeError("ZIP corrupto")
        names = sorted(zf.namelist())
        expected = [f"frame_{i:03d}.png" for i in range(1, 9)]
        if names != expected:
            raise RuntimeError(f"Frames inesperados: {names}")
        from PIL import Image
        for name in names:
            with zf.open(name) as raw:
                if Image.open(raw).size != (540, 1170):
                    raise RuntimeError(f"Dimension invalida en {name}")


def main() -> None:
    validate_zip()
    catalog_before = get_json(IMG_BUCKET, "catalog_index.json")
    manifest_before = fetch_sprite_manifest(load_service_key())
    if any(item.get("id") == SID for item in catalog_before.get("items", [])):
        raise RuntimeError("SID ya existe en catalogo")
    if MANIFEST_KEY in manifest_before:
        raise RuntimeError("manifest_key ya existe")
    try:
        get_json(SCENES_BUCKET, f"{SID}.json")
    except urllib.error.HTTPError as exc:
        if not is_missing(exc):
            raise
    else:
        raise RuntimeError("Spec ya existe")
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() is not None:
        cur.close(); conn.close()
        raise RuntimeError("SID ya existe en Postgres")
    outputs = [ROOT / "SCENE_SPEC_QA.json", ROOT / "UPLOAD_QA_RECEIPT.json"]
    backups = {path: path.read_bytes() if path.exists() else None for path in outputs}
    try:
        pack = upload_sprite_pack(MANIFEST_KEY, ZIP_PATH, service_key=load_service_key())
        result = upload_scene(
        {
            "scene_id": SID,
            "src_dir": str(ROOT),
            "background_file": "live/layers/background.png",
            "bg": {"z": 0, "parallax": 0.0, "scale": 1.26},
            "layers": [],
            "static_file": "static/wallpaper_static.png",
            "particles": [
                {
                    "kind": "motes",
                    "params": {
                        "count": 8,
                        "drift": 0.018,
                        "vy_min": -0.010,
                        "vy_max": -0.002,
                        "color": "#FF4FB8",
                        "max_alpha": 34,
                    },
                }
            ],
            "cycles": [],
            "sprites": [
                {
                    "name": "rainbow_veins_cycle",
                    "manifest_key": MANIFEST_KEY,
                    "behavior": "static",
                    "frame_skip": 5.0,
                    "params": {
                        "fullscreen": False,
                        "x": 0.5,
                        "y": 0.5,
                        "anchor_x": 0.5,
                        "anchor_y": 0.5,
                        "scale": 0.002333333,
                        "alpha": 255,
                        "high_res": True,
                        "z": 12,
                    },
                }
            ],
            "title": {
                "es": "El gatito del arcoiris imposible",
                "en": "The Impossible Rainbow Cat",
            },
            "tags": [
                "gato", "arcoiris", "psicodelico", "humor", "surreal",
                "original", "colores", "animado", "ojos", "pixora",
            ],
            "category_semantic": "funny",
            "glow": "#FF2E9B",
            "name": "El gatito del arcoiris imposible",
            "desc_plain": (
                "Un gato negro descubre que algunas emociones no caben en siete colores: "
                "el arcoiris cobra vida mientras su expresion conserva toda su comedia."
            ),
            "desc_rich": (ROOT / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8"),
            "featured": False,
            "published": False,
            }
        )
        spec = get_json(SCENES_BUCKET, f"{SID}.json")
        spec["published"] = False
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        remote = get_json(SCENES_BUCKET, f"{SID}.json")
        catalog = get_json(IMG_BUCKET, "catalog_index.json")
        matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        db = cur.fetchone()
        manifest_remote = fetch_sprite_manifest(load_service_key())
        if (
            remote.get("published") is not False
            or len(matches) != 1
            or matches[0].get("published") is not False
            or db != (False,)
            or manifest_remote.get(MANIFEST_KEY, {}).get("frames") != 8
        ):
            raise RuntimeError("La escena no quedo triple hidden")
        outputs[0].write_text(json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        receipt = {
            **result, **pack, "published": False, "triple_hidden_verified": True,
            "sprite_frames": 8, "animation": "rainbow hue flow; eye veins remain static",
        }
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM no confirmado")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original_error:
        errors = []
        try: put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        except Exception as exc: errors.append(f"catalogo: {exc}")
        try: put_sprite_manifest(manifest_before, load_service_key())
        except Exception as exc: errors.append(f"manifest: {exc}")
        for bucket, remote_name in OBJECTS:
            try: delete_object(bucket, remote_name)
            except Exception as exc: errors.append(f"{bucket}/{remote_name}: {exc}")
        try:
            cur.execute("DELETE FROM wallpapers WHERE id=%s", (SID,)); conn.commit()
        except Exception as exc: errors.append(f"Postgres: {exc}")
        for path, previous in backups.items():
            try:
                if previous is None: path.unlink(missing_ok=True)
                else: path.write_bytes(previous)
            except Exception as exc: errors.append(f"output {path.name}: {exc}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before:
                errors.append("catalogo no restaurado")
        except Exception as exc: errors.append(f"verificacion catalogo: {exc}")
        try:
            if fetch_sprite_manifest(load_service_key()) != manifest_before:
                errors.append("manifest no restaurado")
        except Exception as exc: errors.append(f"verificacion manifest: {exc}")
        try:
            get_json(SCENES_BUCKET, f"{SID}.json")
        except urllib.error.HTTPError as exc:
            if not is_missing(exc): errors.append(f"spec no verificable: {exc}")
        except Exception as exc: errors.append(f"verificacion spec: {exc}")
        else: errors.append("spec residual")
        try:
            cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (SID,))
            if cur.fetchone() is not None: errors.append("fila Postgres residual")
        except Exception as exc: errors.append(f"verificacion Postgres: {exc}")
        for bucket, remote_name in OBJECTS:
            if bucket == SCENES_BUCKET:
                continue
            try:
                url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote_name}?verify=1"
                with urllib.request.urlopen(url, timeout=20):
                    errors.append(f"objeto residual {bucket}/{remote_name}")
            except urllib.error.HTTPError as exc:
                if not is_missing(exc): errors.append(f"objeto no verificable {bucket}/{remote_name}: {exc}")
            except Exception as exc: errors.append(f"verificacion objeto {bucket}/{remote_name}: {exc}")
        try:
            if not send_catalog_invalidate("wallpapers"):
                print("ADVERTENCIA: FCM compensatorio no confirmado", file=sys.stderr)
        except Exception as exc:
            print(f"ADVERTENCIA: FCM compensatorio fallo: {exc}", file=sys.stderr)
        if errors:
            raise RuntimeError("Rollback incompleto: " + " | ".join(errors)) from original_error
        raise
    finally:
        cur.close(); conn.close()


if __name__ == "__main__":
    main()
