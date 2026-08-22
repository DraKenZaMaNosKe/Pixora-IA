"""Sube la V2 cinematografica de Supergirl como escena privada de QA."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json, upload_scene


ROOT = Path(
    r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/"
    r"wallpapers/1_por_editar/supergirl_crystal_hope_parallax_v2"
)
SID = "supergirl_crystal_hope_parallax_v2"


def main() -> None:
    layers = [
        {
            "key": "shards_far", "file": "layers/shards_far_slowmo.png",
            "z": 5, "parallax": 0.28, "scale": 1.03,
        },
        {
            "key": "krypton_light_rays", "file": "layers/krypton_light_rays.png",
            "z": 6, "parallax": 0.20, "scale": 1.04,
        },
        {
            "key": "shards_mid", "file": "layers/shards_mid_slowmo.png",
            "z": 8, "parallax": 0.50, "scale": 1.05,
        },
        {
            "key": "supergirl", "file": "layers/supergirl_fullbody.png",
            "z": 10, "parallax": 0.72, "scale": 1.0, "bob": [9.0, 7.2],
        },
        {
            "key": "shards_near", "file": "layers/shards_near_slowmo.png",
            "z": 12, "parallax": 0.90, "scale": 1.08,
        },
        {
            "key": "hair_wind_glint", "file": "layers/hair_wind_glint.png",
            "z": 12, "parallax": 0.72, "scale": 1.0, "bob": [9.0, 7.2],
            "bob_phase_source": "supergirl",
        },
        {
            "key": "cape_wind_glint", "file": "layers/cape_wind_glint.png",
            "z": 12, "parallax": 0.72, "scale": 1.0, "bob": [9.0, 7.2],
            "bob_phase_source": "supergirl",
        },
    ]
    for index in range(4):
        layers.append({
            "key": f"emblem_glow_{index}",
            "file": f"layers/emblem_glow_{index}.png",
            "z": 13,
            "parallax": 0.72,
            "scale": 1.0,
            "initial_alpha": 1.0 if index == 0 else 0.0,
            "bob": [9.0, 7.2],
            "bob_phase_source": "supergirl",
        })
    for index in range(3):
        layers.append({
            "key": f"energy_wave_{index}",
            "file": f"layers/energy_wave_{index}.png",
            "z": 14,
            "parallax": 0.72,
            "scale": 1.0,
            "initial_alpha": 1.0 if index == 0 else 0.0,
            "bob": [9.0, 7.2],
            "bob_phase_source": "supergirl",
        })

    upload_scene({
        "scene_id": SID,
        "src_dir": str(ROOT),
        "background_file": "layers/background_crystal_canyon.png",
        "bg": {"z": 0, "parallax": 0.14, "scale": 1.12},
        "layers": layers,
        "static_file": "production/supergirl_crystal_hope_parallax_v2.webp",
        "particles": [{"kind": "motes", "params": {
            "count": 24, "speed": 0.18, "color": "#79E7FF",
            "min_size": 1.0, "max_size": 3.8,
        }}],
        "cycles": [
            {"name": "emblem_pulse", "duration_s": 4.8, "frames": [
                {"layer_key": "emblem_glow_0", "from_s": 0.0, "to_s": 1.2},
                {"layer_key": "emblem_glow_1", "from_s": 1.2, "to_s": 2.4},
                {"layer_key": "emblem_glow_2", "from_s": 2.4, "to_s": 3.2},
                {"layer_key": "emblem_glow_3", "from_s": 3.2, "to_s": 4.0},
                {"layer_key": "emblem_glow_0", "from_s": 4.0, "to_s": 4.8},
            ]},
            {"name": "energy_wave", "duration_s": 5.4, "frames": [
                {"layer_key": "energy_wave_0", "from_s": 0.0, "to_s": 1.8},
                {"layer_key": "energy_wave_1", "from_s": 1.8, "to_s": 3.6},
                {"layer_key": "energy_wave_2", "from_s": 3.6, "to_s": 5.4},
            ]},
        ],
        "sprites": [],
        "title": {"es": "Supergirl · Tiempo de Krypton", "en": "Supergirl · Krypton Time"},
        "tags": ["supergirl", "kara zor-el", "krypton", "dc", "comics", "heroina", "fan art", "slow motion", "parallax"],
        "category_semantic": "comics",
        "glow": "#55DDF5",
        "name": "Supergirl · Tiempo de Krypton",
        "desc_plain": "Kara Zor-El suspende el instante mientras cristales y fragmentos flotan en cámara lenta.",
        "desc_rich": "Una reinterpretación fan art de [[name:Supergirl]], también conocida como [[name:Kara Zor-El]]. La escena congela el instante heroico: los fragmentos cercanos avanzan lentamente hacia la cámara mientras el cañón cristalino conserva una profundidad distinta y el emblema pulsa con energía kryptoniana.",
        "featured": False,
        "published": False,
    })

    # La herramienta genérica conserva solo los campos comunes. Añadimos la
    # deriva cinematográfica soportada por el renderer sin tocar la app.
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    drift_by_key = {
        "background": {"amp_x_pct": 0.18, "amp_y_pct": -0.10, "scale_min": 1.0, "scale_max": 1.012, "rot_deg": 0.12, "period_s": 34.0},
        "shards_far": {"amp_x_pct": 0.35, "amp_y_pct": -0.18, "scale_min": 1.0, "scale_max": 1.018, "rot_deg": 0.45, "period_s": 29.0},
        "shards_mid": {"amp_x_pct": -0.75, "amp_y_pct": 0.32, "scale_min": 1.0, "scale_max": 1.040, "rot_deg": -1.10, "period_s": 23.0},
        "shards_near": {"amp_x_pct": 1.20, "amp_y_pct": -0.52, "scale_min": 1.0, "scale_max": 1.075, "rot_deg": 1.65, "period_s": 18.0},
        "krypton_light_rays": {"amp_x_pct": 0.25, "amp_y_pct": -0.12, "scale_min": 1.0, "scale_max": 1.035, "rot_deg": 0.18, "period_s": 24.0},
    }
    for layer in spec.get("image_layers", []):
        drift = drift_by_key.get(layer.get("key"))
        if drift:
            layer["drift"] = drift
        if layer.get("key") == "hair_wind_glint":
            layer["motion"] = {"kind": "sway", "amplitude_px": 7.0, "period_s": 6.8}
        if layer.get("key") == "cape_wind_glint":
            layer["motion"] = {"kind": "sway", "amplitude_px": 11.0, "period_s": 8.2}
    spec["published"] = False
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"PRIVATE QA READY: {SID} ({len(spec.get('image_layers', []))} layers)")


if __name__ == "__main__":
    main()
