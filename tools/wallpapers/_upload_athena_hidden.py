"""Sube Atenea: estrategia bajo la luna en modo oculto para QA."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene


SID = "atenea_estratega_luna"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"atenea_estratega_luna_20260819"
)


def main() -> None:
    result = upload_scene(
        {
            "scene_id": SID,
            "src_dir": str(ROOT),
            "background_file": "parallax/layers/background.png",
            "bg": {"z": 0, "parallax": 0.07, "scale": 1.26},
            "layers": [
                {
                    "key": "atenea",
                    "file": "parallax/layers/atenea_full.png",
                    "z": 12,
                    "parallax": 0.18,
                    "scale": 1.0,
                    "bob": [1.5, 7.4],
                }
            ],
            "static_file": "static/atenea_estratega_wallpaper.png",
            "particles": [
                {
                    "kind": "motes",
                    "params": {
                        "count": 14,
                        "drift": 0.10,
                        "vy_min": -0.10,
                        "vy_max": -0.025,
                        "min_size": 0.6,
                        "max_size": 2.0,
                        "color": "#F4C875",
                        "max_alpha": 72,
                    },
                }
            ],
            "cycles": [],
            "sprites": [],
            "title": {
                "es": "Atenea: estrategia bajo la luna",
                "en": "Athena: Strategy Beneath the Moon",
            },
            "tags": [
                "atenea", "athena", "minerva", "mitologia griega", "atenas",
                "buho", "olivo", "sabiduria", "estrategia", "anime", "parallax"
            ],
            "category_semantic": "mythology",
            "glow": "#F4C875",
            "name": "Atenea: estrategia bajo la luna",
            "desc_plain": (
                "Atenea vigila la ciudad desde un templo iluminado por la luna, "
                "con su lanza, su escudo y la serenidad de una gran estratega."
            ),
            "desc_rich": (ROOT / "METADATA_DESCRIPCION.md").read_text(encoding="utf-8"),
            "featured": False,
            "published": False,
        }
    )
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    spec["published"] = False
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "UPLOAD_QA_RECEIPT.json").write_text(
        json.dumps({**result, "published": False}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
