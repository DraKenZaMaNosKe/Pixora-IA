"""Reemplaza el ciclo oculto del gatito por venitas sutiles, con rollback."""
from __future__ import annotations

import hashlib
import io
import json
import sys
import urllib.request
import zipfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, PROJECT, SCENES_BUCKET, get_json, put_json
from scene_layer_utils import load_service_key, put_storage_bytes

SID = "gatito_arcoiris_ojos_live"
KEY = "gatito_arcoiris_rainbow_veins_cycle"
SPRITES_BUCKET = "wallpaper-sprites"
EXPECTED_CATALOG = 282
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_arcoiris_psicodelico_20260822")
ZIP_PATH = ROOT / "live" / "sprites" / "rainbow_veins_cycle.zip"
BACKGROUND_PATH = ROOT / "live" / "layers" / "background.png"
STATIC_PATH = ROOT / "static" / "wallpaper_static.png"
RICH_PATH = ROOT / "METADATA_DESCRIPCION.md"
NEW_DESCRIPTION = "Un gato negro descubre que algunas emociones no caben en siete colores: el arcoiris cobra vida mientras su expresion conserva toda su comedia."


def public_bytes(bucket: str, remote: str) -> bytes:
    with urllib.request.urlopen(f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}?nc={time.time_ns()}", timeout=45) as response:
        return response.read()


def main() -> None:
    from PIL import Image

    def webp_bytes(path: Path, size: tuple[int, int] | None = None, quality: int = 94) -> bytes:
        image = Image.open(path).convert("RGB")
        if size:
            image.thumbnail(size, Image.Resampling.LANCZOS)
        out = io.BytesIO()
        image.save(out, "WEBP", quality=quality, method=6)
        return out.getvalue()

    with zipfile.ZipFile(ZIP_PATH) as archive:
        expected = [f"frame_{i:03d}.png" for i in range(1, 9)]
        if archive.namelist() != expected or archive.testzip() is not None:
            raise RuntimeError("ZIP invalido")
        for name in expected:
            with archive.open(name) as raw:
                if Image.open(raw).size != (540, 1170): raise RuntimeError(f"Dimension invalida: {name}")
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    manifest = get_json(SPRITES_BUCKET, "manifest.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if int(catalog.get("version", 0)) != EXPECTED_CATALOG or len(matches) != 1:
        raise RuntimeError("Catalogo cambio")
    if spec.get("published") is not False or matches[0].get("published") is not False:
        raise RuntimeError("Escena no hidden")
    sprites = spec.get("sprites") or []
    if len(sprites) != 1 or sprites[0].get("manifest_key") != KEY:
        raise RuntimeError("Sprite inesperado")
    layers = spec.get("image_layers") or []
    if len(layers) != 1 or layers[0].get("key") != "background":
        raise RuntimeError("Inventario de capas inesperado")
    if layers[0].get("revision") != 8 or abs(float(layers[0].get("scale", 0)) - 1.26) > .0001:
        raise RuntimeError("Revision/escala de fondo inesperada")
    params = sprites[0].get("params") or {}
    expected_params = {
        "fullscreen": False, "x": .5, "y": .5, "anchor_x": .5,
        "anchor_y": .5, "scale": .002333333,
    }
    for key, value in expected_params.items():
        actual = params.get(key)
        if isinstance(value, float):
            if abs(float(actual) - value) > 1e-9: raise RuntimeError(f"Parametro inesperado: {key}")
        elif actual != value:
            raise RuntimeError(f"Parametro inesperado: {key}")
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT published,description,description_rich FROM wallpapers WHERE id=%s", (SID,))
    db_before = cur.fetchone()
    if not db_before or db_before[0] is not False:
        cur.close(); conn.close(); raise RuntimeError("DB no hidden")
    spec_before = json.loads(json.dumps(spec)); catalog_before = json.loads(json.dumps(catalog)); manifest_before = json.loads(json.dumps(manifest))
    old_zip = public_bytes(SPRITES_BUCKET, f"{KEY}.zip")
    asset_names = {
        f"{SID}_background.webp": webp_bytes(BACKGROUND_PATH),
        f"{SID}.webp": webp_bytes(STATIC_PATH),
        f"{SID}_preview.webp": webp_bytes(STATIC_PATH, (540, 1170), 88),
    }
    old_assets = {name: public_bytes(IMG_BUCKET, name) for name in asset_names}
    sk = load_service_key()
    try:
        new_zip = ZIP_PATH.read_bytes()
        put_storage_bytes(SPRITES_BUCKET, f"{KEY}.zip", new_zip, "application/zip", sk)
        manifest[KEY] = {"zip": f"{KEY}.zip", "frames": 8, "size": len(new_zip)}
        expected_manifest = json.loads(json.dumps(manifest))
        put_json(SPRITES_BUCKET, "manifest.json", manifest)
        for name, payload in asset_names.items():
            put_storage_bytes(IMG_BUCKET, name, payload, "image/webp", sk)
        expected_spec = json.loads(json.dumps(spec_before))
        expected_spec["image_layers"][0]["revision"] = 9
        put_json(SCENES_BUCKET, f"{SID}.json", expected_spec)
        matches[0]["description"] = NEW_DESCRIPTION
        catalog["version"] = EXPECTED_CATALOG + 1
        expected_catalog = json.loads(json.dumps(catalog))
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        new_rich = RICH_PATH.read_text(encoding="utf-8")
        cur.execute("UPDATE wallpapers SET description=%s,description_rich=%s,updated_at=now() WHERE id=%s RETURNING published", (NEW_DESCRIPTION, new_rich, SID))
        if cur.fetchone() != (False,): raise RuntimeError("DB metadata fallo")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM fallo")
        remote_zip = public_bytes(SPRITES_BUCKET, f"{KEY}.zip")
        rs = get_json(SCENES_BUCKET, f"{SID}.json"); rc = get_json(IMG_BUCKET, "catalog_index.json"); rm = get_json(SPRITES_BUCKET, "manifest.json")
        cur.execute("SELECT published,description,description_rich FROM wallpapers WHERE id=%s", (SID,)); db = cur.fetchone()
        if rs != expected_spec or db != (False, NEW_DESCRIPTION, new_rich) or rc != expected_catalog or rm != expected_manifest:
            raise RuntimeError("Verificacion remota fallo")
        if hashlib.sha256(remote_zip).digest() != hashlib.sha256(new_zip).digest(): raise RuntimeError("SHA remoto fallo")
        for name, payload in asset_names.items():
            if hashlib.sha256(public_bytes(IMG_BUCKET, name)).digest() != hashlib.sha256(payload).digest():
                raise RuntimeError(f"SHA asset remoto fallo: {name}")
        print(json.dumps({"scene_id": SID, "published": False, "catalog_version": EXPECTED_CATALOG + 1, "revision": 9, "frames": 8, "zip_size": len(new_zip), "sha256": hashlib.sha256(new_zip).hexdigest()}, indent=2))
    except Exception as original_error:
        errors = []
        try: put_storage_bytes(SPRITES_BUCKET, f"{KEY}.zip", old_zip, "application/zip", sk)
        except Exception as exc: errors.append(f"zip: {exc}")
        try: put_json(SPRITES_BUCKET, "manifest.json", manifest_before)
        except Exception as exc: errors.append(f"manifest: {exc}")
        try: put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        except Exception as exc: errors.append(f"catalogo: {exc}")
        try: put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        except Exception as exc: errors.append(f"spec: {exc}")
        for name, payload in old_assets.items():
            try: put_storage_bytes(IMG_BUCKET, name, payload, "image/webp", sk)
            except Exception as exc: errors.append(f"asset {name}: {exc}")
        try:
            cur.execute("UPDATE wallpapers SET published=%s,description=%s,description_rich=%s WHERE id=%s", (db_before[0], db_before[1], db_before[2], SID))
            conn.commit()
        except Exception as exc: errors.append(f"DB restore: {exc}")
        try:
            if get_json(SCENES_BUCKET, f"{SID}.json") != spec_before: errors.append("spec cambio")
        except Exception as exc: errors.append(f"verificacion spec: {exc}")
        try:
            if get_json(IMG_BUCKET, "catalog_index.json") != catalog_before: errors.append("catalogo no restaurado")
        except Exception as exc: errors.append(f"verificacion catalogo: {exc}")
        try:
            if get_json(SPRITES_BUCKET, "manifest.json") != manifest_before: errors.append("manifest no restaurado")
        except Exception as exc: errors.append(f"verificacion manifest: {exc}")
        try:
            if hashlib.sha256(public_bytes(SPRITES_BUCKET, f"{KEY}.zip")).digest() != hashlib.sha256(old_zip).digest(): errors.append("zip no restaurado")
        except Exception as exc: errors.append(f"verificacion zip: {exc}")
        for name, payload in old_assets.items():
            try:
                if hashlib.sha256(public_bytes(IMG_BUCKET, name)).digest() != hashlib.sha256(payload).digest():
                    errors.append(f"asset no restaurado: {name}")
            except Exception as exc: errors.append(f"verificacion asset {name}: {exc}")
        try:
            cur.execute("SELECT published,description,description_rich FROM wallpapers WHERE id=%s", (SID,))
            if cur.fetchone() != db_before: errors.append("DB cambio")
        except Exception as exc: errors.append(f"verificacion DB: {exc}")
        try:
            if not send_catalog_invalidate("wallpapers"): print("ADVERTENCIA FCM compensatorio false", file=sys.stderr)
        except Exception as exc: print(f"ADVERTENCIA FCM: {exc}", file=sys.stderr)
        if errors: raise RuntimeError("Rollback incompleto: " + " | ".join(errors)) from original_error
        raise
    finally:
        cur.close(); conn.close()


if __name__ == "__main__":
    main()
