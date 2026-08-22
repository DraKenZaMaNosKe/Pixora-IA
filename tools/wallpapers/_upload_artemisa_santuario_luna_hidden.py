"""Sube Artemisa: Santuario de la Luna en modo oculto para QA Huawei."""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path[:0] = [str(SCRIPT_DIR.parent), str(SCRIPT_DIR)]

from apply_migration import connect
from _upload_scene_generic import (
    IMG_BUCKET,
    PROJECT,
    SCENES_BUCKET,
    SK,
    get_json,
    put_json,
    upload_scene,
)


SID = "artemisa_santuario_luna"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/artemisa_santuario_luna_20260820")


def is_missing_object(exc: urllib.error.HTTPError) -> bool:
    body = exc.read().decode("utf-8", "replace")
    try:
        payload = json.loads(body)
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
        if not is_missing_object(exc):
            raise


def main() -> None:
    old_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    if any(item.get("id") == SID for item in old_catalog.get("items", [])):
        raise RuntimeError("Artemisa ya existe en catalogo; se requiere actualizador")
    try:
        get_json(SCENES_BUCKET, f"{SID}.json")
    except urllib.error.HTTPError as exc:
        if not is_missing_object(exc):
            raise
    else:
        raise RuntimeError("Artemisa ya tiene spec remoto; se requiere actualizador")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() is not None:
        cur.close()
        conn.close()
        raise RuntimeError("Artemisa ya existe en Postgres; se requiere actualizador")

    try:
        result = upload_scene({
            "scene_id": SID,
            "src_dir": str(ROOT),
            "background_file": "parallax/layers/background.png",
            "bg": {"z": 0, "parallax": 0.06, "scale": 1.26},
            "layers": [
                {"key": "moon_aura", "file": "parallax/layers/moon_aura.png",
                 "z": 8, "parallax": 0.15, "scale": 1.0, "bob": [0.7, 7.8]},
                {"key": "artemis_and_doe", "file": "parallax/layers/artemis_and_doe.png",
                 "z": 12, "parallax": 0.15, "scale": 1.0, "bob": [0.7, 7.8]},
            ],
            "static_file": "static/artemisa_santuario_luna_wallpaper.png",
            "particles": [
                {"kind": "motes", "params": {"count": 14, "drift": 0.055,
                 "vy_min": -0.025, "vy_max": -0.006,
                 "color": "#D6E6FF", "max_alpha": 64}},
            ],
            "cycles": [],
            "sprites": [],
            "title": {"es": "Artemisa: Santuario de la Luna", "en": "Artemis: Sanctuary of the Moon"},
            "tags": ["artemisa", "diana", "apolo", "luna", "caza", "cierva", "mitologia griega",
                     "mitologia romana", "bosque", "parallax"],
            "category_semantic": "mythology",
            "glow": "#BFD7FF",
            "name": "Artemisa: Santuario de la Luna",
            "desc_plain": "Artemisa y una cierva vigilan un santuario forestal bajo una gran luna creciente.",
            "desc_rich": (ROOT / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8"),
            "featured": False,
            "published": False,
        })
        spec = get_json(SCENES_BUCKET, f"{SID}.json")
        spec["published"] = False
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
        spec = get_json(SCENES_BUCKET, f"{SID}.json")
        catalog = get_json(IMG_BUCKET, "catalog_index.json")
        matches = [item for item in catalog.get("items", []) if item.get("id") == SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
        db_row = cur.fetchone()
        if (
            spec.get("published") is not False
            or len(matches) != 1
            or matches[0].get("published") is not False
            or not db_row
            or bool(db_row[0]) is not False
        ):
            raise RuntimeError("Fallo la verificacion triple del estado oculto")
        (ROOT / "SCENE_SPEC_QA.json").write_text(
            json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (ROOT / "UPLOAD_QA_RECEIPT.json").write_text(
            json.dumps({**result, "published": False, "triple_hidden_verified": True},
                       ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    except Exception:
        put_json(IMG_BUCKET, "catalog_index.json", old_catalog)
        for bucket, remote in [
            (SCENES_BUCKET, f"{SID}.json"),
            (IMG_BUCKET, f"{SID}.webp"),
            (IMG_BUCKET, f"{SID}_preview.webp"),
            (IMG_BUCKET, f"{SID}_background.webp"),
            (IMG_BUCKET, f"{SID}_moon_aura.webp"),
            (IMG_BUCKET, f"{SID}_artemis_and_doe.webp"),
        ]:
            delete_object(bucket, remote)
        cur.execute("DELETE FROM wallpapers WHERE id=%s", (SID,))
        conn.commit()
        cur.close()
        conn.close()
        raise
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
