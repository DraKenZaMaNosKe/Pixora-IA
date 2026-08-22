"""Carga Harley Quinn Almacen como canvas_scene oculta para Pixel Studio."""
from pathlib import Path
from _upload_scene_generic import upload_scene

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/harley_quinn_warehouse_parallax")

layers = [
    {"key": "contact_shadow", "file": "layers/contact_shadow.png", "z": 8,
     "parallax": 0.38, "scale": 1.0, "bob": [2.0, 5.6],
     "bob_phase_source": "harley_fullbody"},
    {"key": "harley_fullbody", "file": "layers/harley_fullbody.png", "z": 10,
     "parallax": 0.62, "scale": 1.0, "bob": [2.0, 5.6]},
]
for phase in range(3):
    layers.append({
        "key": f"cards_confetti_{phase}",
        "file": f"layers/cards_confetti_{phase}.png",
        "z": 15, "parallax": 0.76, "scale": 1.0,
        "initial_alpha": 1.0 if phase == 0 else 0.0,
    })

cycles = [{
    "name": "cards_drift", "duration_s": 6.0,
    "frames": [
        {"layer_key": "cards_confetti_0", "from_s": 0.0, "to_s": 2.0},
        {"layer_key": "cards_confetti_1", "from_s": 2.0, "to_s": 4.0},
        {"layer_key": "cards_confetti_2", "from_s": 4.0, "to_s": 6.0},
    ],
}]

if __name__ == "__main__":
    result = upload_scene({
        "scene_id": "harley_quinn_warehouse_parallax",
        "src_dir": str(ROOT),
        "background_file": "layers/background_warehouse.png",
        "bg": {"z": 0, "parallax": 0.09, "scale": 1.07},
        "layers": layers,
        "static_file": "production/harley_quinn_warehouse_parallax.webp",
        "particles": [{"kind": "motes", "params": {
            "count": 12, "speed": 0.08, "color": "#D7A15A",
            "min_size": 1.0, "max_size": 2.8,
        }}],
        "cycles": cycles,
        "sprites": [],
        "title": {"es": "Harley Quinn · Travesura entre bastidores",
                  "en": "Harley Quinn · Backstage Mischief"},
        "tags": ["harley quinn", "dc", "batman", "comics", "arlequin",
                 "fan art", "cartas", "parallax"],
        "category_semantic": "comics",
        "glow": "#E32B48",
        "name": "Harley Quinn · Travesura entre bastidores",
        "desc_plain": "Harley Quinn posa en un almacén teatral entre cartas, rombos y luces rojas y turquesa.",
        "desc_rich": (
            "[[name:Harley Quinn]] es la identidad adoptada por la doctora "
            "[[name:Harleen Quinzel]], antigua psiquiatra de Arkham Asylum. "
            "[[creator:Paul Dini]] y [[creator:Bruce Timm]] la crearon para "
            "[[work:Batman: The Animated Series]], donde debutó en 1992. Su primera "
            "aparición impresa llegó en [[work:The Batman Adventures #12]] en 1993. "
            "Aunque comenzó vinculada al Joker, sus historias posteriores exploran su "
            "independencia, su relación con Poison Ivy y sus papeles como villana, "
            "antihéroe y miembro del Suicide Squad. En esta escena posa entre bastidores "
            "en un almacén abandonado; las cartas flotantes y la iluminación roja y "
            "turquesa reflejan su personalidad teatral, impredecible y juguetona."
        ),
        "featured": False,
        "published": False,
    })
    print(result)
