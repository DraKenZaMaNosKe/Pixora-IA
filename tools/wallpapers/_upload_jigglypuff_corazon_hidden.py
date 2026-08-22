"""Carga Jigglypuff Corazon como canvas_scene oculto para QA en dispositivos."""
from pathlib import Path
from _upload_scene_generic import upload_scene

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/3_publicados/jigglypuff_corazon_parallax")

layers = []
for group in ("a", "b"):
    for phase in range(3):
        layers.append({
            "key": f"hearts_pulse_{group}_{phase}",
            "file": f"layers/hearts_pulse_{group}_{phase}.png",
            "z": 4,
            "parallax": 0.22,
            "scale": 1.0,
            "initial_alpha": 1.0 if phase == 0 else 0.0,
        })
layers.append({
    "key": "character_heart", "file": "layers/character_heart.png",
    "z": 10, "parallax": 0.62, "scale": 1.0, "bob": [4.0, 5.2],
})

cycles = [
    {"name":"heart_pulse_a","duration_s":4.8,"frames":[
        {"layer_key":"hearts_pulse_a_0","from_s":0.0,"to_s":1.6},
        {"layer_key":"hearts_pulse_a_1","from_s":1.6,"to_s":3.2},
        {"layer_key":"hearts_pulse_a_2","from_s":3.2,"to_s":4.0},
        {"layer_key":"hearts_pulse_a_1","from_s":4.0,"to_s":4.8}]},
    {"name":"heart_pulse_b","duration_s":6.2,"frames":[
        {"layer_key":"hearts_pulse_b_0","from_s":0.0,"to_s":2.2},
        {"layer_key":"hearts_pulse_b_1","from_s":2.2,"to_s":4.1},
        {"layer_key":"hearts_pulse_b_2","from_s":4.1,"to_s":5.1},
        {"layer_key":"hearts_pulse_b_1","from_s":5.1,"to_s":6.2}]},
]

if __name__ == "__main__":
    result = upload_scene({
        "scene_id":"jigglypuff_corazon_parallax", "src_dir":str(ROOT),
        "background_file":"layers/background.webp",
        "bg":{"z":0,"parallax":0.08,"scale":1.06},
        "layers":layers,
        "static_file":"production/jigglypuff_corazon_parallax.webp",
        "particles":[], "cycles":cycles, "sprites":[],
        "title":{"es":"Jigglypuff · Corazón encantado","en":"Jigglypuff · Enchanted Heart"},
        "tags":["jigglypuff","pokemon","amor","corazon","romantico","anime","parallax"],
        "category_semantic":"amor", "glow":"#FF4FA3",
        "name":"Jigglypuff · Corazón encantado",
        "desc_plain":"Jigglypuff abraza un corazón encantado entre luces y corazones palpitantes.",
        "desc_rich":"[[name:Jigglypuff]] es el Pokémon Globo número 0039. Su canto puede dormir a quienes lo escuchan. En esta escena romántica abraza un corazón luminoso mientras el fondo responde con pulsos suaves.",
        "featured":False, "published":False,
    })
    print(result)
