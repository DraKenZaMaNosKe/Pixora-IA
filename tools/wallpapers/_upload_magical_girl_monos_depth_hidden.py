"""Carga oculta de la chica magica 2.5D con adornos animados."""
from __future__ import annotations

import io
import json
import sys
import urllib.error
import urllib.request
import zipfile
import time
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, SK, get_json, put, put_json, upload_scene
from sprite_pack_utils import SPRITES_BUCKET, fetch_sprite_manifest, load_service_key, put_sprite_manifest, upload_sprite_pack

SID = "magical_girl_monos_depth_live"
MANIFEST_KEY = "magical_girl_doodles_alive_cycle"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/magical_girl_moños_vivos_20260823")
ZIP_PATH = ROOT / "live/sprites/magical_girl_doodles_alive_cycle.zip"
DEPTH_OBJECT = f"{SID}_background_depth.webp"
OBJECTS = [
    (SCENES_BUCKET, f"{SID}.json"), (IMG_BUCKET, f"{SID}.webp"),
    (IMG_BUCKET, f"{SID}_preview.webp"), (IMG_BUCKET, f"{SID}_background.webp"),
    (IMG_BUCKET, DEPTH_OBJECT), (SPRITES_BUCKET, f"{MANIFEST_KEY}.zip"),
]


def is_missing(exc: urllib.error.HTTPError) -> bool:
    try:
        payload = json.loads(exc.read().decode("utf-8", "replace"))
    except json.JSONDecodeError:
        return False
    return exc.code in {400, 404} and str(payload.get("statusCode")) == "404" and payload.get("code") == "NoSuchKey"


def delete_object(bucket: str, remote: str) -> None:
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}", method="DELETE")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    try:
        with urllib.request.urlopen(req, timeout=30):
            pass
    except urllib.error.HTTPError as exc:
        if not is_missing(exc):
            raise


def public_bytes(bucket: str, remote: str) -> bytes:
    nonce = time.time_ns()
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}?nc={nonce}"
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def validate_assets() -> bytes:
    with zipfile.ZipFile(ZIP_PATH) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("ZIP corrupto")
        names = sorted(archive.namelist())
        if names != [f"frame_{i:03d}.png" for i in range(1, 9)]:
            raise RuntimeError(f"Frames inesperados: {names}")
        for name in names:
            with archive.open(name) as raw, Image.open(raw) as frame:
                if frame.size != (540, 1170) or frame.mode != "RGBA":
                    raise RuntimeError(f"Frame invalido {name}: {frame.mode} {frame.size}")
    depth_path = ROOT / "live/depth/background_depth.png"
    with Image.open(depth_path) as source:
        depth = source.convert("L")
        if depth.size != (1080, 2340):
            raise RuntimeError(f"Depth invalido: {depth.size}")
        lo, hi = depth.getextrema()
        if hi - lo < 80:
            raise RuntimeError(f"Depth sin rango: {lo}..{hi}")
        out = io.BytesIO(); depth.save(out, "WEBP", lossless=True, method=6)
        return out.getvalue()


def main() -> None:
    depth_body = validate_assets()
    catalog_before = get_json(IMG_BUCKET, "catalog_index.json")
    manifest_before = fetch_sprite_manifest(load_service_key())
    if any(x.get("id") == SID for x in catalog_before.get("items", [])) or MANIFEST_KEY in manifest_before:
        raise RuntimeError("SID o manifest ya existe")
    try:
        get_json(SCENES_BUCKET, f"{SID}.json")
    except urllib.error.HTTPError as exc:
        if not is_missing(exc): raise
    else:
        raise RuntimeError("Spec ya existe")
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() is not None:
        cur.close(); conn.close(); raise RuntimeError("SID ya existe en Postgres")
    outputs = [ROOT / "SCENE_SPEC_QA.json", ROOT / "UPLOAD_QA_RECEIPT.json"]
    backups = {p: p.read_bytes() if p.exists() else None for p in outputs}
    try:
        pack = upload_sprite_pack(MANIFEST_KEY, ZIP_PATH, service_key=load_service_key())
        result = upload_scene({
            "scene_id": SID, "src_dir": str(ROOT),
            "background_file": "live/layers/background.png",
            "bg": {"z": 0, "parallax": 0.055, "scale": 1.26},
            "layers": [], "static_file": "static/wallpaper_static.png",
            "particles": [{"kind": "motes", "params": {"count": 9, "drift": .015, "vy_min": -.008, "vy_max": -.002, "color": "#FFF0A8", "max_alpha": 30}}],
            "cycles": [],
            "sprites": [{"name": "doodles_alive", "manifest_key": MANIFEST_KEY, "behavior": "static", "frame_skip": 6.0,
                "params": {"fullscreen": False, "x": .5, "y": .5, "anchor_x": .5, "anchor_y": .5,
                           "scale": .002333333, "alpha": 255, "high_res": True, "parallax_factor": .055, "z": 12}}],
            "title": {"es": "Heroina de los lazos estelares", "en": "Heroine of the Starry Ribbons"},
            "tags": ["anime", "fan art", "homenaje", "chica magica", "sailor moon", "2.5d", "depth map", "lazos", "estrellas", "animado"],
            "category_semantic": "anime", "glow": "#FFD95A", "name": "Heroina de los lazos estelares",
            "desc_plain": "Fan art homenaje a las heroinas magicas noventeras: el escenario gana profundidad 2.5D mientras lazos, lunas, flores y estrellas despiertan en su sitio.",
            "desc_rich": (ROOT / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8"),
            "featured": False, "published": False,
        })
        put(IMG_BUCKET, DEPTH_OBJECT, depth_body)
        spec = get_json(SCENES_BUCKET, f"{SID}.json")
        layers = spec.get("image_layers", [])
        if len(layers) != 1 or layers[0].get("key") != "background": raise RuntimeError("Capas inesperadas")
        layers[0]["depth_map_url"] = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{DEPTH_OBJECT}"
        layers[0]["depth_strength"] = .42
        spec["published"] = False; put_json(SCENES_BUCKET, f"{SID}.json", spec)
        remote = get_json(SCENES_BUCKET, f"{SID}.json")
        catalog = get_json(IMG_BUCKET, "catalog_index.json")
        matches = [x for x in catalog.get("items", []) if x.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,)); db = cur.fetchone()
        rm = fetch_sprite_manifest(load_service_key())
        rlayer = remote.get("image_layers", [{}])[0]
        rsprite = remote.get("sprites", [{}])[0]
        expected_params = {"fullscreen": False, "x": .5, "y": .5, "anchor_x": .5, "anchor_y": .5,
                           "scale": .002333333, "alpha": 255, "high_res": True, "parallax_factor": .055, "z": 12}
        rmanifest = rm.get(MANIFEST_KEY, {})
        if (remote.get("published") is not False or len(matches) != 1 or matches[0].get("published") is not False
                or db != (False,) or rmanifest.get("frames") != 8
                or rmanifest.get("zip") != f"{MANIFEST_KEY}.zip" or rmanifest.get("size") != ZIP_PATH.stat().st_size
                or rlayer.get("revision") != 1 or rlayer.get("scale") != 1.26
                or rlayer.get("parallax_factor") != .055 or rlayer.get("depth_strength") != .42
                or not rlayer.get("depth_map_url", "").endswith(DEPTH_OBJECT)
                or rsprite.get("manifest_key") != MANIFEST_KEY or rsprite.get("frame_skip") != 6.0
                or rsprite.get("params") != expected_params):
            raise RuntimeError("La escena no quedo triple hidden")
        if public_bytes(SPRITES_BUCKET, f"{MANIFEST_KEY}.zip") != ZIP_PATH.read_bytes():
            raise RuntimeError("ZIP remoto no coincide byte a byte")
        if public_bytes(IMG_BUCKET, DEPTH_OBJECT) != depth_body:
            raise RuntimeError("Depth remoto no coincide byte a byte")
        outputs[0].write_text(json.dumps(remote, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        receipt = {**result, **pack, "published": False, "triple_hidden_verified": True, "depth_map": DEPTH_OBJECT, "depth_strength": .42, "catalog_version": catalog.get("version")}
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM no confirmado")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original_error:
        errors = []
        for label, fn in [
            ("catalogo", lambda: put_json(IMG_BUCKET, "catalog_index.json", catalog_before)),
            ("manifest", lambda: put_sprite_manifest(manifest_before, load_service_key())),
        ]:
            try: fn()
            except Exception as exc: errors.append(f"{label}: {exc}")
        for bucket, remote in OBJECTS:
            try: delete_object(bucket, remote)
            except Exception as exc: errors.append(f"{bucket}/{remote}: {exc}")
        try: cur.execute("DELETE FROM wallpapers WHERE id=%s", (SID,)); conn.commit()
        except Exception as exc: errors.append(f"Postgres: {exc}")
        for path, old in backups.items():
            try: path.unlink(missing_ok=True) if old is None else path.write_bytes(old)
            except Exception as exc: errors.append(f"output {path.name}: {exc}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before: errors.append("catalogo no restaurado")
        except Exception as exc: errors.append(f"verify catalogo: {exc}")
        try:
            if fetch_sprite_manifest(load_service_key()) != manifest_before: errors.append("manifest no restaurado")
        except Exception as exc: errors.append(f"verify manifest: {exc}")
        try:
            get_json(SCENES_BUCKET, f"{SID}.json"); errors.append("spec residual")
        except urllib.error.HTTPError as exc:
            if not is_missing(exc): errors.append(f"spec no verificable: {exc}")
        except Exception as exc: errors.append(f"verify spec: {exc}")
        try:
            cur.execute("SELECT 1 FROM wallpapers WHERE id=%s", (SID,))
            if cur.fetchone() is not None: errors.append("DB residual")
        except Exception as exc: errors.append(f"verify DB: {exc}")
        for path, old in backups.items():
            try:
                actual = path.read_bytes() if path.exists() else None
                if actual != old: errors.append(f"output no restaurado {path.name}")
            except Exception as exc: errors.append(f"verify output {path.name}: {exc}")
        for bucket, remote in OBJECTS:
            if bucket == SCENES_BUCKET: continue
            try:
                with urllib.request.urlopen(f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}?rollback=1", timeout=20):
                    errors.append(f"objeto residual {bucket}/{remote}")
            except urllib.error.HTTPError as exc:
                if not is_missing(exc): errors.append(f"objeto no verificable {bucket}/{remote}: {exc}")
            except Exception as exc: errors.append(f"verify objeto {bucket}/{remote}: {exc}")
        try:
            if not send_catalog_invalidate("wallpapers"): errors.append("FCM compensatorio no confirmado")
        except Exception as exc: errors.append(f"FCM compensatorio: {exc}")
        if errors: raise RuntimeError("Rollback incompleto: " + " | ".join(errors)) from original_error
        raise
    finally:
        cur.close(); conn.close()


if __name__ == "__main__":
    main()
