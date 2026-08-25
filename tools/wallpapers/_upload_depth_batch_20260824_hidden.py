"""Upload the approved 2026-08-24 depth-map scenes hidden for device QA."""
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

BASE = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar"
)

SCENES = [
    {
        "scene_id": "andromeda_cadena_nebular_depth",
        "folder": "andromeda_cadena_nebular_20260824",
        "rgb": "production/andromeda_cadena_nebular_1080x2340.png",
        "depth": "production/andromeda_cadena_nebular_depth_1080x2340.png",
        "depth_strength": 0.42,
        "parallax": 0.055,
        "scale": 1.26,
        "title": {"es": "Andromeda: cadena nebular", "en": "Andromeda: Nebula Chain"},
        "name": "Andromeda: cadena nebular",
        "plain": "Shun protege un templo cosmico mientras su cadena atraviesa varios planos de profundidad.",
        "tags": ["andromeda", "shun", "saint seiya", "anime", "fan art", "cadena", "cosmos", "2.5d", "depth map", "parallax"],
        "category": "anime",
        "glow": "#FF4FBF",
        "particles": [{"kind": "motes", "params": {"count": 10, "drift": 0.012, "vy_min": -0.006, "vy_max": -0.001, "color": "#FF83E3", "max_alpha": 28}}],
    },
    {
        "scene_id": "mummra_templo_eclipse_depth",
        "folder": "mummra_templo_eclipse_20260824",
        "rgb": "production/mummra_templo_eclipse_1080x2340.png",
        "depth": "production/mummra_templo_eclipse_depth_1080x2340.png",
        "depth_strength": 0.40,
        "parallax": 0.050,
        "scale": 1.26,
        "title": {"es": "Mumm-Ra: templo del eclipse", "en": "Mumm-Ra: Temple of the Eclipse"},
        "name": "Mumm-Ra: templo del eclipse",
        "plain": "Mumm-Ra desciende de la Piramide Negra bajo un eclipse rojo y guardianes inmoviles.",
        "tags": ["mumm-ra", "thundercats", "fan art", "templo", "eclipse", "villano", "retro", "2.5d", "depth map", "parallax"],
        "category": "gaming",
        "glow": "#FF3526",
        "particles": [{"kind": "embers", "params": {"count": 12, "speed": 0.16, "color": "#FF3526", "min_size": 0.8, "max_size": 2.2}}],
    },
    {
        "scene_id": "sailor_moon_tuxedo_eclipse_depth",
        "folder": "sailor_moon_tuxedo_eclipse_20260824",
        "rgb": "production/sailor_moon_tuxedo_eclipse_1080x2340.png",
        "depth": "production/sailor_moon_tuxedo_eclipse_depth_1080x2340.png",
        "depth_strength": 0.38,
        "parallax": 0.050,
        "scale": 1.26,
        "title": {"es": "Promesa bajo la Luna", "en": "Promise Beneath the Moon"},
        "name": "Sailor Moon y Tuxedo Mask",
        "plain": "Sailor Moon y Tuxedo Mask protegen juntos una terraza del Reino Lunar.",
        "tags": ["sailor moon", "tuxedo mask", "anime", "fan art", "luna", "romance", "magia", "2.5d", "depth map", "parallax"],
        "category": "anime",
        "glow": "#71B7FF",
        "particles": [{"kind": "motes", "params": {"count": 9, "drift": 0.010, "vy_min": -0.005, "vy_max": -0.001, "color": "#FFF0B5", "max_alpha": 24}}],
    },
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


def depth_webp(path: Path) -> bytes:
    with Image.open(path) as source:
        depth = source.convert("L")
        if depth.size != (1080, 2340):
            raise RuntimeError(f"Unexpected depth dimensions for {path}: {depth.size}")
        lo, hi = depth.getextrema()
        if hi - lo < 80:
            raise RuntimeError(f"Insufficient depth range for {path}: {lo}..{hi}")
        out = io.BytesIO()
        depth.save(out, "WEBP", lossless=True, method=6)
        return out.getvalue()


def upload_hidden(cfg: dict) -> dict:
    sid = cfg["scene_id"]
    root = BASE / cfg["folder"]
    depth_object = f"{sid}_background_depth.webp"
    objects = [
        (SCENES_BUCKET, f"{sid}.json"),
        (IMG_BUCKET, f"{sid}.webp"),
        (IMG_BUCKET, f"{sid}_preview.webp"),
        (IMG_BUCKET, f"{sid}_background.webp"),
        (IMG_BUCKET, depth_object),
    ]
    catalog_before = get_json(IMG_BUCKET, "catalog_index.json")
    if any(item.get("id") == sid for item in catalog_before.get("items", [])):
        raise RuntimeError(f"Scene already exists in catalog: {sid}")
    try:
        get_json(SCENES_BUCKET, f"{sid}.json")
    except urllib.error.HTTPError as exc:
        if not is_missing(exc):
            raise
    else:
        raise RuntimeError(f"Scene spec already exists: {sid}")

    depth_body = depth_webp(root / cfg["depth"])
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (sid,))
    if cur.fetchone() is not None:
        cur.close()
        conn.close()
        raise RuntimeError(f"Scene already exists in Postgres: {sid}")
    outputs = [root / "SCENE_SPEC_QA.json", root / "UPLOAD_QA_RECEIPT.json"]
    backups = {path: path.read_bytes() if path.exists() else None for path in outputs}
    try:
        result = upload_scene(
            {
                "scene_id": sid,
                "src_dir": str(root),
                "background_file": cfg["rgb"],
                "bg": {"z": 0, "parallax": cfg["parallax"], "scale": cfg["scale"]},
                "layers": [],
                "static_file": cfg["rgb"],
                "particles": cfg["particles"],
                "cycles": [],
                "sprites": [],
                "title": cfg["title"],
                "tags": cfg["tags"],
                "category_semantic": cfg["category"],
                "glow": cfg["glow"],
                "name": cfg["name"],
                "desc_plain": cfg["plain"],
                "desc_rich": (root / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8"),
                "featured": False,
                "published": False,
            }
        )
        put(IMG_BUCKET, depth_object, depth_body)
        spec = get_json(SCENES_BUCKET, f"{sid}.json")
        layers = spec.get("image_layers", [])
        if len(layers) != 1 or layers[0].get("key") != "background":
            raise RuntimeError(f"Unexpected image layers for {sid}")
        layers[0]["depth_map_url"] = (
            f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{depth_object}"
        )
        layers[0]["depth_strength"] = cfg["depth_strength"]
        spec["published"] = False
        put_json(SCENES_BUCKET, f"{sid}.json", spec)

        remote = get_json(SCENES_BUCKET, f"{sid}.json")
        catalog = get_json(IMG_BUCKET, "catalog_index.json")
        matches = [item for item in catalog.get("items", []) if item.get("id") == sid]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (sid,))
        db = cur.fetchone()
        layer = remote.get("image_layers", [{}])[0]
        if (
            remote.get("published") is not False
            or len(matches) != 1
            or matches[0].get("published") is not False
            or db != (False,)
            or layer.get("depth_strength") != cfg["depth_strength"]
            or not layer.get("depth_map_url", "").endswith(depth_object)
        ):
            raise RuntimeError(f"Scene did not remain triple-hidden: {sid}")

        outputs[0].write_text(
            json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        receipt = {
            **result,
            "published": False,
            "triple_hidden_verified": True,
            "depth_map": depth_object,
            "depth_strength": cfg["depth_strength"],
            "depth_bytes": len(depth_body),
            "catalog_version": catalog.get("version"),
        }
        outputs[1].write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        return receipt
    except Exception as original:
        errors: list[str] = []
        try:
            put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        except Exception as exc:
            errors.append(f"catalog: {exc}")
        for bucket, remote_name in objects:
            try:
                delete_object(bucket, remote_name)
            except Exception as exc:
                errors.append(f"{bucket}/{remote_name}: {exc}")
        try:
            cur.execute("DELETE FROM wallpapers WHERE id=%s", (sid,))
            conn.commit()
        except Exception as exc:
            errors.append(f"Postgres: {exc}")
        for path, previous in backups.items():
            try:
                path.unlink(missing_ok=True) if previous is None else path.write_bytes(previous)
            except Exception as exc:
                errors.append(f"output {path.name}: {exc}")
        try:
            if not send_catalog_invalidate("wallpapers"):
                errors.append("compensating FCM not confirmed")
        except Exception as exc:
            errors.append(f"compensating FCM: {exc}")
        if errors:
            raise RuntimeError("Incomplete rollback: " + " | ".join(errors)) from original
        raise
    finally:
        cur.close()
        conn.close()


def main() -> None:
    receipts = [upload_hidden(cfg) for cfg in SCENES]
    if not send_catalog_invalidate("wallpapers"):
        raise RuntimeError("Final FCM invalidation was not confirmed")
    print(json.dumps(receipts, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
