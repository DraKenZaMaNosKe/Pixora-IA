"""Upload Gatitos: baile entre estrellas as a private QA canvas scene."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene
from sprite_pack_utils import load_service_key, upload_sprite_pack


SID = "gatitos_baile_cosmico"
MANIFEST_KEY = "gatitos_baile_cosmico_dance"
ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatitos_baile_cosmico"
)


def main() -> None:
    metadata = json.loads((ROOT / "METADATA.json").read_text(encoding="utf-8"))
    pack = upload_sprite_pack(
        MANIFEST_KEY,
        ROOT / "production" / "gatitos_baile_cosmico_sprite.zip",
        service_key=load_service_key(),
    )
    result = upload_scene({
        "scene_id": SID,
        "src_dir": str(ROOT),
        "background_file": "production/gatitos_baile_cosmico_background.png",
        "bg": {"z": 0, "parallax": 0.10, "scale": 1.14},
        "layers": [
            {
                "key": "ambient_glow",
                "file": "production/gatitos_baile_cosmico_glow.png",
                "z": 3,
                "parallax": 0.22,
                "scale": 1.06,
                "bob": [5.0, 8.5],
            },
            {
                "key": "contact_shadow",
                "file": "production/gatitos_baile_cosmico_shadow.png",
                "z": 8,
                "parallax": 0.48,
                "scale": 1.02,
            },
        ],
        "static_file": "production/gatitos_baile_cosmico.webp",
        "particles": [{
            "kind": "motes",
            "params": {
                "count": 18,
                "drift": 0.22,
                "vy_min": -0.28,
                "vy_max": -0.08,
                "min_size": 1.0,
                "max_size": 3.0,
                "color": "#A9F4FF",
                "max_alpha": 105,
            },
        }],
        "cycles": [],
        "sprites": [{
            "name": "gatitos",
            "manifest_key": MANIFEST_KEY,
            "behavior": "static",
            # 60 Hz / 2 ticks = ~30 fps: baile enérgico, continuo y orgánico.
            "frame_skip": 2,
            "params": {
                "x": 0.5,
                "y": 0.75,
                "scale": 0.00269,
                "alpha": 255,
                "high_res": False,
                "parallax_factor": 0.64,
                "z": 10,
            },
        }],
        "title": {"es": "Gatitos: baile entre estrellas", "en": "Kittens: Dance Among Stars"},
        "tags": ["gatitos", "gatos", "baile", "espacio", "animado", "tierno", "parallax"],
        "category_semantic": "animals",
        "glow": "#B946FF",
        "name": "Gatitos: baile entre estrellas",
        "desc_plain": (
            "Nube y Chispa se inclinan al mismo ritmo sobre una pista cósmica y convierten cada paso en una pequeña fiesta."
        ),
        "desc_rich": metadata["description_rich"],
        "featured": False,
        "published": False,
    })
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    spec["published"] = False
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    receipt = {**result, **pack, "published": False, "sprite_count": len(spec.get("sprites", []))}
    (ROOT / "UPLOAD_QA_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
