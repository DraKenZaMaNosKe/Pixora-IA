"""Sube el gatito curioso oculto y listo para QA en dispositivo."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene
from sprite_pack_utils import load_service_key, upload_sprite_pack

SID = "gatito_curioso_parpadeo"
MANIFEST_KEY = "gatito_curioso_parpadeo_gatito"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_curioso_parpadeo_20260812")


def main() -> None:
    pack = upload_sprite_pack(
        MANIFEST_KEY, ROOT / "production" / "gatito_curioso_parpadeo_sprite.zip",
        service_key=load_service_key())
    result = upload_scene({
        "scene_id": SID, "src_dir": str(ROOT),
        "background_file": "parallax/layers/background.png",
        "bg": {"z": 0, "parallax": 0.0, "scale": 1.15},
        "layers": [], "static_file": "static/gatito_curioso_static.png",
        "particles": [{"kind": "motes", "params": {
            "count": 10, "drift": 0.22, "vy_min": -0.18, "vy_max": -0.05,
            "min_size": 0.8, "max_size": 2.2, "color": "#FFD27A", "max_alpha": 75}}],
        "cycles": [],
        "sprites": [{"name": "gatito", "manifest_key": MANIFEST_KEY,
                     "behavior": "static", "frame_skip": 8,
                     "params": {"x": 0.095, "y": 0.825, "scale": 0.00235,
                                "alpha": 255, "high_res": False,
                                "parallax_factor": 0.0, "z": 10}}],
        "title": {"es": "Gatito curioso tras la pared", "en": "Curious Cat Behind the Wall"},
        "tags": ["gatito", "gato", "curioso", "parpadeo", "tierno", "humor", "parallax"],
        "category_semantic": "animals", "glow": "#FFB52E",
        "name": "Gatito curioso tras la pared",
        "desc_plain": "Un gatito de enorme ojo ámbar vigila la habitación, parpadea y se sorprende detrás de la pared.",
        "desc_rich": (ROOT / "README_ESCENA.md").read_text(encoding="utf-8"),
        "featured": False, "published": False,
    })
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    spec["published"] = False
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    receipt = {**result, **pack, "published": False,
               "layers": len(spec.get("image_layers", [])),
               "sprites": len(spec.get("sprites", []))}
    (ROOT / "UPLOAD_QA_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
