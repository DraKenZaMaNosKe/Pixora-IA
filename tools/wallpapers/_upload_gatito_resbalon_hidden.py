"""Sube Gatito contra la gravedad como escena privada de QA."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene
from sprite_pack_utils import load_service_key, upload_sprite_pack


SID = "gatito_resbalon_pared"
MANIFEST_KEY = "gatito_resbalon_pared_gato"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_resbalon_pared")


def main() -> None:
    pack = upload_sprite_pack(
        MANIFEST_KEY,
        ROOT / "production" / "gatito_resbalon_sprite.zip",
        service_key=load_service_key(),
    )
    result = upload_scene({
        "scene_id": SID,
        "src_dir": str(ROOT),
        "background_file": "production/background.png",
        "bg": {"z": 0, "parallax": 0.08, "scale": 1.24},
        "layers": [],
        "static_file": "production/gatito_resbalon_flat.jpg",
        "particles": [],
        "cycles": [],
        "sprites": [{
            "name": "gatito",
            "manifest_key": MANIFEST_KEY,
            "behavior": "static",
            "frame_skip": 24,
            "params": {
                "x": 0.61,
                "y": 0.53,
                "scale": 0.00520,
                "alpha": 255,
                "high_res": False,
            },
        }],
        "title": {"es": "Gatito contra la gravedad", "en": "Kitten vs. Gravity"},
        "tags": ["gato", "gatito", "humor", "pared", "escalar", "resbalon", "minimalista", "animado", "amoled"],
        "category_semantic": "funny",
        "glow": "#F6AA35",
        "name": "Gatito contra la gravedad",
        "desc_plain": "Un gatito testarudo resbala por la pared, se asusta y vuelve a escalar antes de tocar el piso.",
        "desc_rich": "Este personaje caricaturesco original convierte una pequeña crisis en comedia. Sus ojos enormes siguen cada pata mientras las garras pierden terreno. La escena habla de perseverancia: resbalar no es fracasar si todavía puedes volver a sujetarte. Seis poses completas forman un ciclo ligero con descenso, susto, recuperación y escalada.",
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
