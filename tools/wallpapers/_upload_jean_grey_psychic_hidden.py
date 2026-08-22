"""Carga Jean Grey Pulso Psiquico como canvas_scene oculta para Pixel Studio."""
from pathlib import Path
from _upload_scene_generic import upload_scene

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/jean_grey_psychic_parallax")

layers = [
    {"key": "jean_grey_fullbody", "file": "layers/jean_grey_fullbody.png",
     "z": 10, "parallax": 0.60, "scale": 1.0, "bob": [3.0, 5.8]},
]
for phase in range(3):
    layers.append({
        "key": f"psychic_pulse_{phase}",
        "file": f"layers/psychic_pulse_{phase}.png",
        "z": 15,
        "parallax": 0.63,
        "scale": 1.0,
        "bob": [3.0, 5.8],
        "bob_phase_source": "jean_grey_fullbody",
        "initial_alpha": 1.0 if phase == 0 else 0.0,
    })

cycles = [{
    "name": "psychic_pulse",
    "duration_s": 4.2,
    "frames": [
        {"layer_key": "psychic_pulse_0", "from_s": 0.0, "to_s": 1.4},
        {"layer_key": "psychic_pulse_1", "from_s": 1.4, "to_s": 2.8},
        {"layer_key": "psychic_pulse_2", "from_s": 2.8, "to_s": 3.5},
        {"layer_key": "psychic_pulse_1", "from_s": 3.5, "to_s": 4.2},
    ],
}]

if __name__ == "__main__":
    result = upload_scene({
        "scene_id": "jean_grey_psychic_parallax",
        "src_dir": str(ROOT),
        "background_file": "layers/background_danger_astral.png",
        "bg": {"z": 0, "parallax": 0.10, "scale": 1.07},
        "layers": layers,
        "static_file": "production/jean_grey_psychic_parallax.webp",
        "particles": [{"kind": "motes", "params": {
            "count": 14, "speed": 0.10, "color": "#FF55E8",
            "min_size": 1.0, "max_size": 3.0,
        }}],
        "cycles": cycles,
        "sprites": [],
        "title": {"es": "Jean Grey · Pulso psíquico", "en": "Jean Grey · Psychic Pulse"},
        "tags": ["jean grey", "x-men", "marvel", "telepatia", "telequinesis",
                 "fenix", "comics", "fan art", "parallax"],
        "category_semantic": "comics",
        "glow": "#FF55E8",
        "name": "Jean Grey · Pulso psíquico",
        "desc_plain": "Jean Grey abre un pulso telequinético entre la Sala de Peligro y un plano astral.",
        "desc_rich": (
            "[[name:Jean Grey]] es una de las integrantes fundadoras de los [[name:X-Men]]. "
            "Debutó como Marvel Girl en [[work:X-Men #1]] (1963), creada por "
            "[[creator:Stan Lee]] y [[creator:Jack Kirby]]. Sus poderes principales son la "
            "telepatía y la telequinesis. Su historia está profundamente vinculada con la "
            "[[name:Fuerza Fénix]], entidad cósmica relacionada con vida, muerte y renacimiento. "
            "La célebre Saga de Fénix Oscura exploró el peligro de un poder casi ilimitado y el "
            "conflicto entre control, emoción y responsabilidad. En esta escena, el entorno frío "
            "de entrenamiento se abre hacia un plano astral naranja mientras Jean concentra una "
            "onda psíquica magenta en su mano."
        ),
        "featured": False,
        "published": False,
    })
    print(result)
