"""Sube Poseidón: reino abismal en modo oculto para revisión."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene


SID = "poseidon_reino_abismal"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"poseidon_reino_abismal_20260818"
)


def main() -> None:
    result = upload_scene(
        {
            "scene_id": SID,
            "src_dir": str(ROOT),
            "background_file": "parallax/layers/background_overscan.png",
            "bg": {"z": 0, "parallax": 0.07, "scale": 1.26},
            "layers": [
                {
                    "key": "poseidon",
                    "file": "parallax/layers/poseidon_full_1080x2340.png",
                    "z": 12,
                    "parallax": 0.18,
                    "scale": 1.0,
                    "bob": [2.2, 6.8],
                }
            ],
            "static_file": "static/poseidon_reino_abismal_estatico.png",
            "particles": [
                {
                    "kind": "bubbles",
                    "params": {
                        "count": 18,
                        "speed": 0.17,
                        "min_size": 1.2,
                        "max_size": 4.8,
                        "color": "#8FEAFF",
                        "max_alpha": 110,
                    },
                },
                {
                    "kind": "motes",
                    "params": {
                        "count": 12,
                        "drift": 0.10,
                        "vy_min": -0.08,
                        "vy_max": -0.02,
                        "min_size": 0.6,
                        "max_size": 2.0,
                        "color": "#44D9FF",
                        "max_alpha": 68,
                    },
                },
            ],
            "cycles": [],
            "sprites": [],
            "title": {
                "es": "Poseidón: soberano del reino abismal",
                "en": "Poseidon: Sovereign of the Abyssal Kingdom",
            },
            "tags": [
                "poseidon", "mitologia griega", "neptuno", "tridente",
                "oceano", "ruinas", "dioses", "parallax", "fantasia",
            ],
            "category_semantic": "mythology",
            "glow": "#39D8FF",
            "name": "Poseidón: soberano del reino abismal",
            "desc_plain": (
                "Poseidón custodia un reino sumergido entre ruinas, medusas, "
                "corrientes luminosas y una criatura colosal en la distancia."
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
