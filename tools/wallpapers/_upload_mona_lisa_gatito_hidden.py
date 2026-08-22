"""Sube Mona Lisa y el gatito en modo oculto para revisión en Pixel Studio."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene
from sprite_pack_utils import load_service_key, upload_sprite_pack


SID = "mona_lisa_gatito_museo"
MANIFEST_KEY = "mona_lisa_gatito_museo_pair"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"mona_lisa_gatito_museo_20260818"
)


def main() -> None:
    pack = upload_sprite_pack(
        MANIFEST_KEY,
        ROOT / "production" / "mona_lisa_gatito_museo_pair.zip",
        service_key=load_service_key(),
    )
    result = upload_scene(
        {
            "scene_id": SID,
            "src_dir": str(ROOT),
            "background_file": "parallax/layers/background.png",
            "bg": {"z": 0, "parallax": 0.07, "scale": 1.26},
            "layers": [],
            "static_file": "static/mona_lisa_gatito_wallpaper_estatico.png",
            "particles": [
                {
                    "kind": "motes",
                    "params": {
                        "count": 9,
                        "drift": 0.12,
                        "vy_min": -0.10,
                        "vy_max": -0.03,
                        "min_size": 0.7,
                        "max_size": 1.8,
                        "color": "#D8B56A",
                        "max_alpha": 52,
                    },
                }
            ],
            "cycles": [],
            "sprites": [
                {
                    "name": "mona_cat",
                    "manifest_key": MANIFEST_KEY,
                    "behavior": "static",
                    "frame_skip": 10,
                    "params": {
                        "x": 0.50,
                        "y": 0.61,
                        "scale": 0.00078,
                        "alpha": 255,
                        "high_res": True,
                        "parallax_factor": 0.16,
                        "z": 10,
                    },
                }
            ],
            "title": {
                "es": "Mona Lisa y el visitante inesperado",
                "en": "Mona Lisa and the Unexpected Visitor",
            },
            "tags": [
                "arte",
                "renacimiento",
                "mona lisa",
                "leonardo",
                "gato",
                "museo",
                "parpadeo",
                "parallax",
            ],
            "category_semantic": "art",
            "glow": "#D8B56A",
            "name": "Mona Lisa y el visitante inesperado",
            "desc_plain": (
                "Una reinterpretación renacentista: Lisa Gherardini y un gatito "
                "naranja comparten una mirada, un parpadeo y un pequeño misterio."
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
    receipt = {
        **result,
        **pack,
        "published": False,
        "layers": len(spec.get("image_layers", [])),
        "sprites": len(spec.get("sprites", [])),
    }
    (ROOT / "UPLOAD_QA_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
