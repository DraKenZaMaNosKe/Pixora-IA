"""Sube Perséfone: Entre Dos Reinos en modo oculto para QA Huawei."""
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


SID = "persefone_dos_reinos"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/persefone_dos_reinos_20260820")


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
        raise RuntimeError("Perséfone ya existe en catalogo; se requiere actualizador")
    try:
        get_json(SCENES_BUCKET, f"{SID}.json")
    except urllib.error.HTTPError as exc:
        if not is_missing_object(exc):
            raise
    else:
        raise RuntimeError("Perséfone ya tiene spec remoto; se requiere actualizador")

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT published FROM wallpapers WHERE id=%s", (SID,))
    if cur.fetchone() is not None:
        cur.close()
        conn.close()
        raise RuntimeError("Perséfone ya existe en Postgres; se requiere actualizador")

    try:
        result = upload_scene({
            "scene_id": SID,
            "src_dir": str(ROOT),
            "background_file": "parallax/layers/background.png",
            "bg": {"z": 0, "parallax": 0.06, "scale": 1.26},
            "layers": [
                {"key": "dual_aura", "file": "parallax/layers/dual_aura.png",
                 "z": 8, "parallax": 0.13, "scale": 1.0, "bob": [0.6, 8.2]},
                {"key": "persephone_full", "file": "parallax/layers/persephone_full.png",
                 "z": 12, "parallax": 0.13, "scale": 1.0, "bob": [0.6, 8.2]},
            ],
            "static_file": "static/persefone_dos_reinos_wallpaper.png",
            "particles": [
                {"kind": "motes", "params": {"count": 7, "drift": 0.040,
                 "vy_min": -0.018, "vy_max": -0.004,
                 "color": "#C98CFF", "max_alpha": 64}},
                {"kind": "motes", "params": {"count": 7, "drift": 0.036,
                 "vy_min": -0.016, "vy_max": -0.003,
                 "color": "#FFD870", "max_alpha": 60}},
            ],
            "cycles": [],
            "sprites": [],
            "title": {"es": "Perséfone: Entre Dos Reinos", "en": "Persephone: Between Two Realms"},
            "tags": ["persefone", "proserpina", "demeter", "hades", "granada", "primavera", "inframundo", "mitologia griega",
                     "mitologia romana", "flores", "dos reinos", "parallax"],
            "category_semantic": "mythology",
            "glow": "#C98CFF",
            "name": "Perséfone: Entre Dos Reinos",
            "desc_plain": "Perséfone equilibra la primavera y el inframundo con una granada y flores entre dos reinos.",
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
            (IMG_BUCKET, f"{SID}_dual_aura.webp"),
            (IMG_BUCKET, f"{SID}_persephone_full.webp"),
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


