"""Sube Plancton con hamburguesa como escena privada para QA en dispositivo."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene
from sprite_pack_utils import load_service_key, upload_sprite_pack


SID = "plancton_hamburguesa_escape"
MANIFEST_KEY = "plancton_hamburguesa_escape_plancton"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/plancton_hamburguesa_escape")


def main() -> None:
    pack = upload_sprite_pack(
        MANIFEST_KEY,
        ROOT / "production" / "plancton_hamburguesa_sprite.zip",
        service_key=load_service_key(),
    )
    result = upload_scene({
        "scene_id": SID,
        "src_dir": str(ROOT),
        "background_file": "source/grok-480084d4-11fb-47e7-a72c-a6fe1c11be97.jpg",
        "bg": {"z": 0, "parallax": 0.09, "scale": 1.24},
        "layers": [],
        "static_file": "production/plancton_hamburguesa_flat.jpg",
        "particles": [{
            "kind": "motes",
            "params": {
                "count": 14, "drift": 0.45, "vy_min": -0.48, "vy_max": -0.18,
                "min_size": 1.0, "max_size": 3.0, "color": "#D8F7FF", "max_alpha": 105,
            },
        }],
        "cycles": [],
        "sprites": [{
            "name": "plancton",
            "manifest_key": MANIFEST_KEY,
            "behavior": "static",
            "frame_skip": 12,
            "params": {
                "x": 0.49805304247265453, "y": 0.8612303224712381, "scale": 0.0030,
                "alpha": 255, "high_res": False, "parallax_factor": 0.42, "z": 10,
            },
        }],
        "title": {"es": "Plancton: escape con la hamburguesa", "en": "Plankton's Burger Escape"},
        "tags": [
            "plancton", "sheldon", "bob esponja", "fondo de bikini", "hamburguesa",
            "balde de carnada", "comedia", "animado", "parallax", "caricatura",
        ],
        "category_semantic": "cartoons",
        "glow": "#49D6E8",
        "name": "Plancton: escape con la hamburguesa",
        "desc_plain": "Plancton avanza con su enorme premio, presume su victoria y se sobresalta como si Don Cangrejo estuviera a punto de descubrirlo.",
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
