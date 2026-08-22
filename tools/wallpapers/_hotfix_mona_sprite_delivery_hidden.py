"""Restore Mona's stable sprite key with the corrected four-paw animation, hidden-first."""
from __future__ import annotations

import hashlib
import json
import sys
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(SCRIPT_DIR.parent))

from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json
from scene_layer_utils import load_service_key, put_storage_bytes

SID = "mona_lisa_gatito_museo"
CURRENT_KEY = "mona_lisa_gatito_museo_pair_v2"
STABLE_KEY = "mona_lisa_gatito_museo_pair"
SPRITES_BUCKET = "wallpaper-sprites"
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
EXPECTED_CATALOG = 266
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/mona_lisa_gatito_museo_20260818")
ZIP_PATH = ROOT / "production" / "mona_lisa_gatito_museo_pair_v3_local_four_paws.zip"


def public_bytes(bucket: str, remote: str) -> bytes:
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=45) as response:
        return response.read()


def main() -> None:
    with zipfile.ZipFile(ZIP_PATH) as archive:
        expected = [f"frame_{i:03d}.png" for i in range(1, 6)]
        if archive.namelist() != expected or archive.testzip() is not None:
            raise RuntimeError("ZIP anatómico inválido")
        from PIL import Image
        for name in expected:
            with archive.open(name) as source:
                if Image.open(source).size != (970, 1411):
                    raise RuntimeError(f"Geometría inesperada: {name}")

    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    manifest = get_json(SPRITES_BUCKET, "manifest.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    if int(catalog.get("version", 0)) != EXPECTED_CATALOG or len(matches) != 1:
        raise RuntimeError("Catálogo cambió; no se aplicará el hotfix")
    if spec.get("published") is not True or matches[0].get("published") is not True:
        raise RuntimeError("Mona no parte publicada")
    sprites = spec.get("sprites") or []
    layers = spec.get("image_layers") or []
    if len(sprites) != 1 or sprites[0].get("manifest_key") != CURRENT_KEY:
        raise RuntimeError("Sprite remoto inesperado")
    if len(layers) != 1 or layers[0].get("key") != "background" or int(layers[0].get("revision", 0)) != 3:
        raise RuntimeError("Fondo remoto inesperado")

    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() != (True,):
        cur.close(); conn.close(); raise RuntimeError("Postgres no parte publicado")

    spec_before = json.loads(json.dumps(spec))
    catalog_before = json.loads(json.dumps(catalog))
    manifest_before = json.loads(json.dumps(manifest))
    old_zip = public_bytes(SPRITES_BUCKET, f"{STABLE_KEY}.zip")
    outputs = [ROOT / "SCENE_SPEC_DELIVERY_FIX_QA.json", ROOT / "DELIVERY_FIX_UPLOAD_RECEIPT.json"]
    output_backups = {p: p.read_bytes() if p.exists() else None for p in outputs}
    sk = load_service_key()
    try:
        spec["published"] = False
        matches[0]["published"] = False
        catalog["version"] = EXPECTED_CATALOG + 1
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute("UPDATE wallpapers SET published=false WHERE id=%s RETURNING published", (SID,))
        if cur.fetchone() != (False,): raise RuntimeError("No se ocultó en DB")
        conn.commit()

        zip_bytes = ZIP_PATH.read_bytes()
        put_storage_bytes(SPRITES_BUCKET, f"{STABLE_KEY}.zip", zip_bytes, "application/zip", sk)
        manifest[STABLE_KEY] = {"zip": f"{STABLE_KEY}.zip", "frames": 5, "size": len(zip_bytes)}
        put_json(SPRITES_BUCKET, "manifest.json", manifest)
        spec["sprites"][0]["manifest_key"] = STABLE_KEY
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM falló")

        rs = get_json(SCENES_BUCKET, f"{SID}.json")
        rc = get_json(IMG_BUCKET, "catalog_index.json")
        rm = get_json(SPRITES_BUCKET, "manifest.json")
        rmatch = [i for i in rc.get("items", []) if i.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        if rs.get("published") is not False or len(rmatch) != 1 or rmatch[0].get("published") is not False or cur.fetchone() != (False,):
            raise RuntimeError("La escena no quedó triple-hidden")
        expected_spec = json.loads(json.dumps(spec_before)); expected_spec["published"] = False
        expected_spec["sprites"][0]["manifest_key"] = STABLE_KEY
        if rs != expected_spec or int(rc.get("version", 0)) != EXPECTED_CATALOG + 1:
            raise RuntimeError("El spec cambió fuera del hotfix permitido")
        remote_zip = public_bytes(SPRITES_BUCKET, f"{STABLE_KEY}.zip")
        if hashlib.sha256(remote_zip).digest() != hashlib.sha256(zip_bytes).digest():
            raise RuntimeError("ZIP remoto no coincide")
        if (rm.get(STABLE_KEY) or {}).get("frames") != 5:
            raise RuntimeError("Manifest estable inválido")

        receipt = {"scene_id": SID, "updated_at": datetime.now(timezone.utc).isoformat(),
                   "catalog_version": EXPECTED_CATALOG + 1, "published": False,
                   "manifest_key": STABLE_KEY, "frames": 5, "frame_canvas": [970, 1411],
                   "sha256": hashlib.sha256(zip_bytes).hexdigest(), "qa_pending": ["HUAWEI VNS-L53"]}
        outputs[0].write_text(json.dumps(rs, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        outputs[1].write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception as original_error:
        conn.rollback()
        put_storage_bytes(SPRITES_BUCKET, f"{STABLE_KEY}.zip", old_zip, "application/zip", sk)
        put_json(SPRITES_BUCKET, "manifest.json", manifest_before)
        put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        cur.execute("UPDATE wallpapers SET published=true WHERE id=%s", (SID,)); conn.commit()
        for path, data in output_backups.items():
            if data is None: path.unlink(missing_ok=True)
            else: path.write_bytes(data)
        restored_spec = get_json(SCENES_BUCKET, f"{SID}.json")
        restored_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        restored_manifest = get_json(SPRITES_BUCKET, "manifest.json")
        restored_matches = [i for i in restored_catalog.get("items", []) if i.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        restored_db = cur.fetchone()
        restored_zip = public_bytes(SPRITES_BUCKET, f"{STABLE_KEY}.zip")
        if (restored_spec != spec_before or restored_catalog != catalog_before or
                restored_manifest != manifest_before or restored_matches[0].get("published") is not True or
                restored_db != (True,) or hashlib.sha256(restored_zip).digest() != hashlib.sha256(old_zip).digest()):
            raise RuntimeError("Rollback del hotfix quedó incompleto") from original_error
        try:
            if not send_catalog_invalidate("wallpapers"):
                print("ADVERTENCIA: FCM compensatorio devolvió false", file=sys.stderr)
        except Exception as fcm_error:
            print(f"ADVERTENCIA: FCM compensatorio falló: {fcm_error}", file=sys.stderr)
        raise original_error
    finally:
        cur.close(); conn.close()


if __name__ == "__main__":
    main()
