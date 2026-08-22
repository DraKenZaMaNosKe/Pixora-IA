"""Sube Pícaro tras la puerta roja en modo oculto para QA en dispositivo."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene
from sprite_pack_utils import load_service_key, upload_sprite_pack


SID = "picaro_puerta_roja"
MANIFEST_KEY = "picaro_puerta_roja_blink"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/"
    r"picaro_puerta_roja_20260818"
)


def main() -> None:
    pack = upload_sprite_pack(
        MANIFEST_KEY,
        ROOT / "production" / "picaro_puerta_roja_blink.zip",
        service_key=load_service_key(),
    )
    result = upload_scene(
        {
            "scene_id": SID,
            "src_dir": str(ROOT),
            "background_file": "parallax/layers/background_door.png",
            "bg": {"z": 0, "parallax": 0.07, "scale": 1.26},
            "layers": [
                {
                    "key": "foreground_door",
                    "file": "parallax/layers/foreground_door.png",
                    "z": 20,
                    "parallax": 0.07,
                    "scale": 1.26,
                }
            ],
            "static_file": "static/picaro_puerta_wallpaper_estatico.png",
            "particles": [
                {
                    "kind": "motes",
                    "params": {
                        "count": 7,
                        "drift": 0.08,
                        "vy_min": -0.07,
                        "vy_max": -0.02,
                        "min_size": 0.6,
                        "max_size": 1.5,
                        "color": "#FFB06A",
                        "max_alpha": 42,
                    },
                }
            ],
            "cycles": [],
            "sprites": [
                {
                    "name": "picaro",
                    "manifest_key": MANIFEST_KEY,
                    "behavior": "static",
                    "frame_skip": 10,
                    "params": {
                        "x": 0.493,
                        "y": 0.650,
                        "scale": 0.000925926,
                        "alpha": 255,
                        "high_res": True,
                        "parallax_factor": 0.15,
                        "z": 10,
                    },
                }
            ],
            "title": {
                "es": "Pícaro tras la puerta roja",
                "en": "Mischief Behind the Red Door",
            },
            "tags": [
                "gato", "tierno", "puerta roja", "misterio", "parpadeo",
                "parallax", "original", "pixora"
            ],
            "category_semantic": "animals",
            "glow": "#FF4A32",
            "name": "Pícaro tras la puerta roja",
            "desc_plain": (
                "Un curioso gatito blanco y negro se asoma detrás de una puerta "
                "roja, parpadea y vigila la habitación sin dejarse descubrir."
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
