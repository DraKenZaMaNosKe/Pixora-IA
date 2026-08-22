"""Upload Supergirl Crystal Hope as a private Pixel Studio scene."""
from pathlib import Path

from _upload_scene_generic import upload_scene


ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/supergirl_crystal_hope_parallax")
SID = "supergirl_crystal_hope_parallax"


if __name__ == "__main__":
    layers = [{
        "key": "supergirl",
        "file": "layers/supergirl_fullbody.png",
        "z": 10,
        "parallax": 0.62,
        "scale": 1.0,
        "bob": [3.5, 5.8],
    }]
    for i in range(4):
        layers.append({
            "key": f"emblem_glow_{i}",
            "file": f"layers/emblem_glow_{i}.png",
            "z": 13,
            "parallax": 0.58,
            "scale": 1.0,
            "initial_alpha": 1.0 if i == 0 else 0.0,
            "bob": [3.5, 5.8],
            "bob_phase_source": "supergirl",
        })
    upload_scene({
        "scene_id": SID,
        "src_dir": str(ROOT),
        "background_file": "layers/background_crystal_canyon.png",
        "bg": {"z": 0, "parallax": 0.10, "scale": 1.10},
        "layers": layers,
        "static_file": "production/supergirl_crystal_hope_parallax.webp",
        "particles": [{"kind": "motes", "params": {
            "count": 18, "speed": 0.12, "color": "#79E7FF",
            "min_size": 1.0, "max_size": 3.2,
        }}],
        "cycles": [{"name": "emblem_pulse", "duration_s": 4.8, "frames": [
            {"layer_key": "emblem_glow_0", "from_s": 0.0, "to_s": 1.2},
            {"layer_key": "emblem_glow_1", "from_s": 1.2, "to_s": 2.4},
            {"layer_key": "emblem_glow_2", "from_s": 2.4, "to_s": 3.2},
            {"layer_key": "emblem_glow_3", "from_s": 3.2, "to_s": 4.0},
            {"layer_key": "emblem_glow_0", "from_s": 4.0, "to_s": 4.8},
        ]}],
        "sprites": [],
        "title": {"es": "Supergirl · Esperanza de Krypton", "en": "Supergirl · Hope of Krypton"},
        "tags": ["supergirl", "kara zor-el", "krypton", "dc", "comics", "heroina", "fan art", "live", "parallax"],
        "category_semantic": "comics",
        "glow": "#55DDF5",
        "name": "Supergirl · Esperanza de Krypton",
        "desc_plain": "Kara Zor-El avanza entre cristales azules y fragmentos dorados mientras su emblema pulsa con energía.",
        "desc_rich": "[[name:Supergirl]], cuyo nombre kryptoniano es [[name:Kara Zor-El]], es prima de Superman y superviviente de Krypton. Su debut moderno ocurrió en [[work:Action Comics #252]] (1959), escrito por [[creator:Otto Binder]] y dibujado por [[creator:Al Plastino]]. Bajo un sol amarillo posee fuerza, velocidad, vuelo, invulnerabilidad, visión calorífica, visión de rayos X, superoído y aliento helado. A diferencia de su primo criado en la Tierra, Kara conserva recuerdos directos de la cultura y la pérdida de Krypton. En pantalla ha sido interpretada por Helen Slater, Melissa Benoist, Sasha Calle y Milly Alcock, protagonista de [[work:Supergirl]] (2026), dirigida por Craig Gillespie. Esta composición es fan art: muestra a Kara emergiendo de un cañón cristalino mientras el azul representa su legado, el rojo su determinación y las fracturas doradas un nuevo comienzo.",
        "featured": False,
        "published": False,
    })
