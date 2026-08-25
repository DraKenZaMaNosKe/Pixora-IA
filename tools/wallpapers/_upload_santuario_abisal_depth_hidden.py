"""Carga oculta de la primera escena Pixora con mapa de profundidad 2.5D."""
from __future__ import annotations

import io
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import (
    IMG_BUCKET,
    PROJECT,
    SCENES_BUCKET,
    SK,
    get_json,
    put,
    put_json,
    upload_scene,
)

SID = "santuario_abisal_depth_2_5d"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"santuario_abisal_depth_2_5d_20260823"
)
DEPTH_OBJECT = f"{SID}_background_depth.webp"
OBJECTS = [
    (SCENES_BUCKET, f"{SID}.json"),
    (IMG_BUCKET, f"{SID}.webp"),
    (IMG_BUCKET, f"{SID}_preview.webp"),
    (IMG_BUCKET, f"{SID}_background.webp"),
    (IMG_BUCKET, DEPTH_OBJECT),
]


def missing(exc: urllib.error.HTTPError) -> bool:
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
        if not missing(exc):
            raise


def depth_webp() -> bytes:
    path = ROOT / "production/santuario_abisal_depth_1080x2340.png"
    with Image.open(path) as source:
        depth = source.convert("L")
        if depth.size != (1080, 2340):
            raise RuntimeError(f"Mapa depth inesperado: {depth.size}")
        lo, hi = depth.getextrema()
        if hi - lo < 80:
            raise RuntimeError(f"Mapa depth sin rango suficiente: {lo}..{hi}")
        out = io.BytesIO()
        depth.save(out, "WEBP", lossless=True, method=6)
        return out.getvalue()


def main() -> None:
    catalog_before = get_json(IMG_BUCKET, "catalog_index.json")
    if any(item.get("id") == SID for item in catalog_before.get("items", [])):
        raise RuntimeError("La escena ya existe en catálogo")
    try:
        get_json(SCENES_BUCKET, f"{SID}.json")
    except urllib.error.HTTPError as exc:
        if not missing(exc):
            raise
    else:
        raise RuntimeError("La escena ya tiene spec")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() is not None:
        cur.close()
        conn.close()
        raise RuntimeError("La escena ya existe en Postgres")

    outputs = [ROOT / "SCENE_SPEC_QA.json", ROOT / "UPLOAD_QA_RECEIPT.json"]
    backups = {p: p.read_bytes() if p.exists() else None for p in outputs}
    try:
        result = upload_scene(
            {
                "scene_id": SID,
                "src_dir": str(ROOT),
                "background_file": "production/santuario_abisal_1080x2340.png",
                "bg": {"z": 0, "parallax": 0.06, "scale": 1.26},
                "layers": [],
                "static_file": "production/santuario_abisal_1080x2340.png",
                "particles": [
                    {
                        "kind": "motes",
                        "params": {
                            "count": 10,
                            "drift": 0.02,
                            "vy_min": -0.010,
                            "vy_max": -0.002,
                            "color": "#64E8FF",
                            "max_alpha": 38,
                        },
                    }
                ],
                "cycles": [],
                "sprites": [],
                "title": {
                    "es": "Santuario abisal: memoria de las profundidades",
                    "en": "Abyssal Sanctuary: Memory of the Deep",
                },
                "tags": [
                    "2.5d",
                    "depth map",
                    "profundidad",
                    "océano",
                    "ruinas",
                    "medusas",
                    "fantasía",
                    "original",
                    "parallax",
                ],
                "category_semantic": "fantasy",
                "glow": "#64E8FF",
                "name": "Santuario abisal 2.5D",
                "desc_plain": (
                    "Una exploradora descubre un santuario submarino que cobra "
                    "volumen mediante un mapa de profundidad 2.5D real."
                ),
                "desc_rich": (ROOT / "METADATA_DESCRIPCION.md").read_text(
                    encoding="utf-8"
                ),
                "featured": False,
                "published": False,
            }
        )

        depth_body = depth_webp()
        put(IMG_BUCKET, DEPTH_OBJECT, depth_body)

        spec = get_json(SCENES_BUCKET, f"{SID}.json")
        layers = spec.get("image_layers", [])
        if len(layers) != 1 or layers[0].get("key") != "background":
            raise RuntimeError("Inventario de capas inesperado")
        layers[0]["depth_map_url"] = (
            f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{DEPTH_OBJECT}"
        )
        layers[0]["depth_strength"] = 0.72
        spec["published"] = False
        put_json(SCENES_BUCKET, f"{SID}.json", spec)

        remote = get_json(SCENES_BUCKET, f"{SID}.json")
        catalog = get_json(IMG_BUCKET, "catalog_index.json")
        matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        db = cur.fetchone()
        remote_layer = remote.get("image_layers", [{}])[0]
        if (
            remote.get("published") is not False
            or len(matches) != 1
            or matches[0].get("published") is not False
            or db != (False,)
            or remote_layer.get("depth_strength") != 0.72
            or not remote_layer.get("depth_map_url", "").endswith(DEPTH_OBJECT)
        ):
            raise RuntimeError("La escena depth no quedó triple hidden o perdió el mapa")

        outputs[0].write_text(
            json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        receipt = {
            **result,
            "published": False,
            "triple_hidden_verified": True,
            "depth_map": DEPTH_OBJECT,
            "depth_strength": 0.72,
            "depth_bytes": len(depth_body),
            "catalog_version": catalog.get("version"),
        }
        outputs[1].write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM no confirmado")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original_error:
        cleanup_errors: list[str] = []
        try:
            put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        except Exception as cleanup_error:
            cleanup_errors.append(f"catálogo: {cleanup_error}")
        for bucket, remote_name in OBJECTS:
            try:
                delete_object(bucket, remote_name)
            except Exception as cleanup_error:
                cleanup_errors.append(f"{bucket}/{remote_name}: {cleanup_error}")
        try:
            cur.execute("DELETE FROM wallpapers WHERE id=%s", (SID,))
            conn.commit()
        except Exception as cleanup_error:
            cleanup_errors.append(f"Postgres: {cleanup_error}")
        for path, previous in backups.items():
            try:
                if previous is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_bytes(previous)
            except Exception as cleanup_error:
                cleanup_errors.append(f"output {path.name}: {cleanup_error}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before:
                cleanup_errors.append("catálogo no restaurado")
        except Exception as cleanup_error:
            cleanup_errors.append(f"verificación catálogo: {cleanup_error}")
        try:
            get_json(SCENES_BUCKET, f"{SID}.json")
        except urllib.error.HTTPError as exc:
            if not missing(exc):
                cleanup_errors.append(f"spec no verificable: {exc}")
        except Exception as cleanup_error:
            cleanup_errors.append(f"verificación spec: {cleanup_error}")
        else:
            cleanup_errors.append("spec residual")
        try:
            cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (SID,))
            if cur.fetchone() is not None:
                cleanup_errors.append("fila Postgres residual")
        except Exception as cleanup_error:
            cleanup_errors.append(f"verificación Postgres: {cleanup_error}")
        try:
            if not send_catalog_invalidate("wallpapers"):
                print("ADVERTENCIA: FCM compensatorio no confirmado", file=sys.stderr)
        except Exception as fcm_error:
            print(f"ADVERTENCIA: falló FCM compensatorio: {fcm_error}", file=sys.stderr)
        if cleanup_errors:
            raise RuntimeError("Rollback incompleto: " + " | ".join(cleanup_errors)) from original_error
        raise
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
