"""Oculta Mona Lisa, instala el sprite anatómicamente corregido y deja QA pendiente."""
from __future__ import annotations

import json
import hashlib
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
OLD_KEY = "mona_lisa_gatito_museo_pair"
NEW_KEY = "mona_lisa_gatito_museo_pair_v2"
SPRITES_BUCKET = "wallpaper-sprites"
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"mona_lisa_gatito_museo_20260818"
)
ZIP_PATH = ROOT / "production" / "mona_lisa_gatito_museo_pair_v3_local_four_paws.zip"


def public_bytes(bucket: str, remote: str) -> bytes:
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read()


def main() -> None:
    if not ZIP_PATH.is_file() or ZIP_PATH.stat().st_size < 100_000:
        raise RuntimeError("Falta ZIP anatómico V3")
    with zipfile.ZipFile(ZIP_PATH) as archive:
        names = archive.namelist()
        expected_names = [f"frame_{i:03d}.png" for i in range(1, 6)]
        if names != expected_names or archive.testzip() is not None:
            raise RuntimeError("Contenido ZIP inválido")
        from PIL import Image
        for name in names:
            with archive.open(name) as source:
                if Image.open(source).size != (970, 1411):
                    raise RuntimeError(f"Geometría inválida en {name}")
    sk = load_service_key()
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    manifest = get_json(SPRITES_BUCKET, "manifest.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
    sprites = spec.get("sprites") or []
    layers = spec.get("image_layers") or []
    if len(matches) != 1 or len(sprites) != 1 or len(layers) != 1:
        raise RuntimeError("Inventario remoto inesperado")
    sprite = sprites[0]
    if not spec.get("published") or not matches[0].get("published"):
        raise RuntimeError("La escena no parte publicada")
    if sprite.get("manifest_key") != OLD_KEY:
        raise RuntimeError("Manifest anterior inesperado")
    if NEW_KEY in manifest:
        raise RuntimeError("La clave V2 ya existe; no se sobrescribirá a ciegas")
    if int(layers[0].get("revision", 0)) != 3 or abs(float(layers[0].get("scale", 0)) - 1.26) > .001:
        raise RuntimeError("El fondo aprobado cambió")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    row = cur.fetchone()
    if not row or not bool(row[0]):
        cur.close(); conn.close()
        raise RuntimeError("Postgres no parte publicado")

    spec_before = json.loads(json.dumps(spec))
    catalog_before = json.loads(json.dumps(catalog))
    manifest_before = json.loads(json.dumps(manifest))
    output_paths = [ROOT / "SCENE_SPEC_ANATOMY_V2_QA.json", ROOT / "ANATOMY_V2_UPLOAD_RECEIPT.json"]
    output_backups = {path: path.read_bytes() if path.exists() else None for path in output_paths}
    wrote_zip = False
    try:
        # Ocultar primero: nunca exponer un spec que apunte a un paquete a medio subir.
        spec["published"] = False
        matches[0]["published"] = False
        catalog["version"] = int(catalog.get("version", 0) or 0) + 1
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute("UPDATE wallpapers SET published=false WHERE id=%s RETURNING published", (SID,))
        if cur.fetchone() != (False,):
            raise RuntimeError("No se pudo ocultar en Postgres")
        conn.commit()

        zip_bytes = ZIP_PATH.read_bytes()
        put_storage_bytes(SPRITES_BUCKET, f"{NEW_KEY}.zip", zip_bytes, "application/zip", sk)
        wrote_zip = True
        manifest[NEW_KEY] = {"zip": f"{NEW_KEY}.zip", "frames": 5, "size": len(zip_bytes)}
        put_json(SPRITES_BUCKET, "manifest.json", manifest)
        sprite["manifest_key"] = NEW_KEY
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        if not send_catalog_invalidate("wallpapers"):
            raise RuntimeError("FCM no confirmó invalidación")

        remote_spec = get_json(SCENES_BUCKET, f"{SID}.json")
        remote_catalog = get_json(IMG_BUCKET, "catalog_index.json")
        remote_manifest = get_json(SPRITES_BUCKET, "manifest.json")
        remote_matches = [i for i in remote_catalog.get("items", []) if i.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        db_state = cur.fetchone()
        if remote_spec.get("published") or len(remote_matches) != 1 or remote_matches[0].get("published"):
            raise RuntimeError("La escena no quedó oculta")
        if db_state != (False,):
            raise RuntimeError("Postgres no quedó oculto")
        remote_sprite = (remote_spec.get("sprites") or [{}])[0]
        pack = remote_manifest.get(NEW_KEY) or {}
        if remote_sprite.get("manifest_key") != NEW_KEY or int(pack.get("frames", 0)) != 5:
            raise RuntimeError("El nuevo paquete no quedó enlazado")
        remote_zip = public_bytes(SPRITES_BUCKET, f"{NEW_KEY}.zip")
        if hashlib.sha256(remote_zip).digest() != hashlib.sha256(ZIP_PATH.read_bytes()).digest():
            raise RuntimeError("El ZIP remoto no coincide byte por byte")
        expected_spec = json.loads(json.dumps(spec_before))
        expected_spec["published"] = False
        expected_spec["sprites"][0]["manifest_key"] = NEW_KEY
        if remote_spec != expected_spec:
            raise RuntimeError("El spec cambió fuera de published/manifest_key")

        receipt = {
            "scene_id": SID,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "catalog_version": remote_catalog.get("version"),
            "published": False,
            "manifest_key_before": OLD_KEY,
            "manifest_key_after": NEW_KEY,
            "frames": 5,
            "frame_canvas": [970, 1411],
            "anatomy": {"front_legs": 2, "hind_legs": 2, "total_legs": 4},
            "qa_pending": ["HUAWEI VNS-L53"],
        }
        (ROOT / "SCENE_SPEC_ANATOMY_V2_QA.json").write_text(
            json.dumps(remote_spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (ROOT / "ANATOMY_V2_UPLOAD_RECEIPT.json").write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    except Exception:
        conn.rollback()
        put_json(SCENES_BUCKET, f"{SID}.json", spec_before)
        put_json(IMG_BUCKET, "catalog_index.json", catalog_before)
        put_json(SPRITES_BUCKET, "manifest.json", manifest_before)
        cur.execute("UPDATE wallpapers SET published=%s WHERE id=%s", (True, SID))
        conn.commit()
        send_catalog_invalidate("wallpapers")
        for path, data in output_backups.items():
            if data is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(data)
        # The versioned orphan ZIP is harmless and intentionally retained if written;
        # it is unreachable after restoring the manifest and avoids destructive cleanup.
        raise
    finally:
        cur.close(); conn.close()


if __name__ == "__main__":
    main()
