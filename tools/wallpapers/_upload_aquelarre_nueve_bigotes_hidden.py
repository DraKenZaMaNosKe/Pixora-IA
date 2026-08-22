"""Sube El aquelarre de los nueve bigotes como escena privada de QA."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene


ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/aquelarre_nueve_bigotes_parallax")
SID = "aquelarre_nueve_bigotes_parallax"


def main() -> None:
    layers = []
    for index in range(3):
        layers.append({
            "key": f"scarlet_glow_{index}", "file": f"layers/scarlet_glow_{index}.png",
            "z": 5, "parallax": 0.10, "scale": 1.24,
            "initial_alpha": 1.0 if index == 0 else 0.0,
        })
    for index in range(3):
        layers.append({
            "key": f"eyes_{index}", "file": f"layers/eyes_{index}.png",
            "z": 12, "parallax": 0.10, "scale": 1.24,
            "initial_alpha": 1.0 if index == 0 else 0.0,
        })
    layers.extend([
        {"key": "candle_auras", "file": "layers/candle_auras.png", "z": 9, "parallax": 0.10, "scale": 1.24},
        {"key": "book_aura", "file": "layers/book_aura.png", "z": 10, "parallax": 0.10, "scale": 1.24},
    ])

    upload_scene({
        "scene_id": SID, "src_dir": str(ROOT),
        "background_file": "layers/background_master.png",
        "bg": {"z": 0, "parallax": 0.10, "scale": 1.24},
        "layers": layers,
        "static_file": "production/aquelarre_nueve_bigotes.webp",
        # Sin particulas globales: el renderer las dibuja sobre los gatos y
        # pueden parecer cuentas de colores o defectos en sus collares.
        "particles": [],
        "cycles": [
            {"name": "scarlet_fire", "duration_s": 3.6, "frames": [
                {"layer_key": "scarlet_glow_0", "from_s": 0.0, "to_s": 1.2},
                {"layer_key": "scarlet_glow_1", "from_s": 1.2, "to_s": 2.4},
                {"layer_key": "scarlet_glow_2", "from_s": 2.4, "to_s": 3.6},
            ]},
            {"name": "cat_blink", "duration_s": 7.0, "frames": [
                {"layer_key": "eyes_0", "from_s": 0.0, "to_s": 5.7},
                {"layer_key": "eyes_1", "from_s": 5.7, "to_s": 6.1},
                {"layer_key": "eyes_2", "from_s": 6.1, "to_s": 6.35},
                {"layer_key": "eyes_1", "from_s": 6.35, "to_s": 6.65},
                {"layer_key": "eyes_0", "from_s": 6.65, "to_s": 7.0},
            ]},
        ],
        "sprites": [],
        "title": {"es": "El aquelarre de los nueve bigotes", "en": "The Coven of Nine Whiskers"},
        "tags": ["gatos", "gothic", "oculto", "grabado", "luna roja", "velas", "amoled", "fantasia", "parallax"],
        "category_semantic": "fantasy",
        "glow": "#FF3526",
        "name": "El aquelarre de los nueve bigotes",
        "desc_plain": "Tres gatos solemnes custodian un libro imposible bajo la luna roja y un círculo de velas.",
        "desc_rich": "Una escena original de fantasía gótica con tres guardianes felinos. El gato negro central vigila el libro; el tuxedo parece el escéptico del aquelarre y el atigrado aporta humor con su gesto cansado. Las marcas del libro y el círculo son símbolos decorativos inventados. La estética imita un grabado de tinta limitada en negro AMOLED, rojo escarlata y marfil envejecido.",
        "featured": False, "published": False,
    })

    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    shared_drift = {"amp_x_pct": 0.16, "amp_y_pct": -0.10, "scale_min": 1.0, "scale_max": 1.012, "rot_deg": 0.08, "period_s": 30.0}
    for layer in spec.get("image_layers", []):
        layer["drift"] = shared_drift
        if layer.get("key") == "candle_auras":
            layer["motion"] = {"kind": "alpha_pulse", "min_alpha": 0.34, "max_alpha": 0.95, "period_s": 1.8}
        elif layer.get("key") == "book_aura":
            layer["motion"] = {"kind": "alpha_pulse", "min_alpha": 0.12, "max_alpha": 0.62, "period_s": 5.5}
    spec["published"] = False
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    (ROOT / "SCENE_SPEC_QA.json").write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PRIVATE QA READY: {SID} ({len(spec.get('image_layers', []))} layers)")


if __name__ == "__main__":
    main()
