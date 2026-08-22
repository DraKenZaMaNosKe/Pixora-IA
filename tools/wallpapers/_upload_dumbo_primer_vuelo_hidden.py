"""Sube Dumbo: el primer vuelo entre sueños como escena privada de QA."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene
from sprite_pack_utils import load_service_key, upload_sprite_pack


SID = "dumbo_primer_vuelo"
MANIFEST_KEY = "dumbo_primer_vuelo_dumbo"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/dumbo_primer_vuelo")


def main() -> None:
    pack = upload_sprite_pack(
        MANIFEST_KEY,
        ROOT / "production" / "dumbo_primer_vuelo_sprite.zip",
        service_key=load_service_key(),
    )
    result = upload_scene({
        "scene_id": SID,
        "src_dir": str(ROOT),
        "background_file": "source/1-Photo-1.jpg",
        "bg": {"z": 0, "parallax": 0.08, "scale": 1.24},
        "layers": [],
        "static_file": "production/dumbo_primer_vuelo_flat.jpg",
        "particles": [{
            "kind": "motes",
            "params": {
                "count": 18, "drift": 0.34, "vy_min": -0.24, "vy_max": -0.08,
                "min_size": 1.0, "max_size": 3.2, "color": "#FFF3FC", "max_alpha": 135,
            },
        }],
        "cycles": [],
        "sprites": [{
            "name": "dumbo",
            "manifest_key": MANIFEST_KEY,
            "behavior": "static",
            "frame_skip": 10,
            "params": {
                "x": 0.52, "y": 0.47, "scale": 0.00315,
                "alpha": 255, "high_res": False, "parallax_factor": 0.40, "z": 10,
            },
        }],
        "title": {"es": "Dumbo: el primer vuelo entre sueños", "en": "Dumbo: First Flight Through Dreams"},
        "tags": [
            "dumbo", "elefante", "vuelo", "nubes", "acuarela", "fantasia",
            "ternura", "infantil", "animado", "parallax", "clasico",
        ],
        "category_semantic": "cartoons",
        "glow": "#F6B7D2",
        "name": "Dumbo: el primer vuelo entre sueños",
        "desc_plain": "Dumbo flota entre nubes de acuarela y transforma aquello que lo hacía diferente en la libertad de volar.",
        "desc_rich": (ROOT / "metadata" / "APP_DESCRIPTION_RICH.txt").read_text(encoding="utf-8").strip(),
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
