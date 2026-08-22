"""Sube Zeus: Trono de la tormenta en modo oculto para QA."""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(SCRIPT_DIR.parent))

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


SID = "zeus_trono_tormenta"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/zeus_trono_tormenta_20260820")


def delete_object(bucket: str, remote: str) -> None:
    """Elimina solo objetos de esta alta; 404 significa que no llegó a crearse."""
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}", method="DELETE"
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("apikey", SK)
    try:
        with urllib.request.urlopen(req, timeout=30):
            pass
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise


def main() -> None:
    old_catalog = get_json(IMG_BUCKET, "catalog_index.json")
    if any(item.get("id") == SID for item in old_catalog.get("items", [])):
        raise RuntimeError("Zeus ya existe en el catálogo; se requiere un actualizador, no alta nueva")
    try:
        get_json(SCENES_BUCKET, f"{SID}.json")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = {}
        missing = (
            exc.code in {400, 404}
            and str(payload.get("statusCode")) == "404"
            and payload.get("code") == "NoSuchKey"
        )
        if not missing:
            raise
    else:
        raise RuntimeError("Zeus ya tiene spec remoto; se requiere un actualizador, no alta nueva")
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() is not None:
        cur.close()
        conn.close()
        raise RuntimeError("Zeus ya existe en Postgres; se requiere un actualizador")
    try:
        result = upload_scene({
        "scene_id": SID,
        "src_dir": str(ROOT),
        "background_file": "parallax/layers/background.png",
        "bg": {"z": 0, "parallax": 0.06, "scale": 1.26},
        "layers": [
            {"key": "lightning_aura", "file": "parallax/layers/lightning_aura.png", "z": 8,
             "parallax": 0.18, "scale": 1.0, "bob": [1.2, 7.4]},
            {"key": "zeus", "file": "parallax/layers/zeus_full.png", "z": 12,
             "parallax": 0.18, "scale": 1.0, "bob": [1.2, 7.4]},
        ],
        "static_file": "static/zeus_trono_tormenta_wallpaper.png",
        "particles": [
            {"kind": "motes", "params": {"count": 15, "drift": 0.10,
             "vy_min": -0.08, "vy_max": -0.015,
             "color": "#FFD66B", "max_alpha": 88}},
        ],
        "cycles": [],
        "sprites": [],
        "title": {"es": "Zeus: Trono de la tormenta", "en": "Zeus: Throne of the Storm"},
        "tags": ["zeus", "júpiter", "olimpo", "rayo", "águila", "tormenta",
                 "mitología griega", "mitología romana", "parallax"],
        "category_semantic": "mythology",
        "glow": "#FFD66B",
        "name": "Zeus: Trono de la tormenta",
        "desc_plain": "Zeus sostiene el rayo sobre una terraza del Olimpo mientras la tormenta se detiene a su alrededor.",
        "desc_rich": (ROOT / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8"),
        "featured": False,
        "published": False,
        })
        spec = get_json(SCENES_BUCKET, f"{SID}.json")
        spec["published"] = False
        put_json(SCENES_BUCKET, f"{SID}.json", spec)
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
            raise RuntimeError("Falló la verificación triple del estado oculto")
        (ROOT / "SCENE_SPEC_QA.json").write_text(
            json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (ROOT / "UPLOAD_QA_RECEIPT.json").write_text(
            json.dumps({**result, "published": False, "triple_hidden_verified": True}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    except Exception:
        put_json(IMG_BUCKET, "catalog_index.json", old_catalog)
        for bucket, remote in [
            (SCENES_BUCKET, f"{SID}.json"),
            (IMG_BUCKET, f"{SID}.webp"),
            (IMG_BUCKET, f"{SID}_preview.webp"),
            (IMG_BUCKET, f"{SID}_background.webp"),
            (IMG_BUCKET, f"{SID}_lightning_aura.webp"),
            (IMG_BUCKET, f"{SID}_zeus.webp"),
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
