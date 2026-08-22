"""Sube Hades y Cerbero en modo oculto para QA."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene

SID = "hades_cerbero_umbral"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"hades_cerbero_umbral_20260819"
)


def main() -> None:
    result = upload_scene({
        "scene_id": SID,
        "src_dir": str(ROOT),
        "background_file": "parallax/layers/background.png",
        "bg": {"z": 0, "parallax": 0.06, "scale": 1.26},
        "layers": [
            {"key": "hades", "file": "parallax/layers/hades_full.png", "z": 10,
             "parallax": 0.15, "scale": 1.0, "bob": [1.2, 8.2]},
            {"key": "cerberus", "file": "parallax/layers/cerberus_full.png", "z": 14,
             "parallax": 0.21, "scale": 1.0, "bob": [1.8, 6.6]},
        ],
        "static_file": "static/hades_cerbero_wallpaper.png",
        "particles": [
            {"kind": "motes", "params": {"count": 16, "drift": 0.11,
             "vy_min": -0.09, "vy_max": -0.02, "min_size": 0.7,
             "max_size": 2.3, "color": "#826BFF", "max_alpha": 76}},
        ],
        "cycles": [], "sprites": [],
        "title": {"es": "Hades y Cerbero: guardianes del umbral",
                  "en": "Hades and Cerberus: Guardians of the Threshold"},
        "tags": ["hades", "cerbero", "kerberos", "perséfone", "inframundo",
                 "mitología griega", "plutón", "anime", "parallax"],
        "category_semantic": "mythology",
        "glow": "#826BFF",
        "name": "Hades y Cerbero: guardianes del umbral",
        "desc_plain": "Hades custodia el Inframundo junto a Cerbero, el perro de tres cabezas que vigila sus puertas.",
        "desc_rich": (ROOT / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8"),
        "featured": False, "published": False,
    })
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    spec["published"] = False
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ROOT / "UPLOAD_QA_RECEIPT.json").write_text(
        json.dumps({**result, "published": False}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")


if __name__ == "__main__":
    main()
