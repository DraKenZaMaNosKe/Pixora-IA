"""Carga Magneto Soberano del Metal oculto para Pixel Studio."""
from datetime import datetime, timezone
from pathlib import Path
from _upload_scene_generic import upload_scene, get_json, put_json, IMG_BUCKET, SCENES_BUCKET

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/magneto_soberano_metal_parallax")
SID = "magneto_soberano_metal_parallax"

far_drift = {"amp_x_pct":0.25,"amp_y_pct":-0.18,"scale_min":1.0,"scale_max":1.008,"rot_deg":0.35,"period_s":11.0}
near_drift = {"amp_x_pct":-0.32,"amp_y_pct":0.22,"scale_min":1.0,"scale_max":1.012,"rot_deg":-0.5,"period_s":9.0}

layers = [
    {"key":"metal_far","file":"layers/metal_far.png","z":5,"parallax":0.28,"scale":1.0},
    {"key":"magneto_fullbody","file":"layers/magneto_fullbody.png","z":10,"parallax":0.58,"scale":1.0,"bob":[5.0,5.6]},
]
for i in range(3):
    layers.append({"key":f"magnetic_pulse_{i}","file":f"layers/magnetic_pulse_{i}.png","z":13,"parallax":0.60,"scale":1.0,"bob":[5.0,5.6]})
layers.append({"key":"metal_near","file":"layers/metal_near.png","z":18,"parallax":0.82,"scale":1.0})

cycles=[{"name":"magnetic_pulse","duration_s":4.8,"frames":[
    {"layer_key":"magnetic_pulse_0","from_s":0.0,"to_s":1.6},
    {"layer_key":"magnetic_pulse_1","from_s":1.6,"to_s":3.2},
    {"layer_key":"magnetic_pulse_2","from_s":3.2,"to_s":4.0},
    {"layer_key":"magnetic_pulse_1","from_s":4.0,"to_s":4.8},
]}]

if __name__ == "__main__":
    result=upload_scene({
        "scene_id":SID,"src_dir":str(ROOT),
        "background_file":"layers/background_ruined_city.png",
        "bg":{"z":0,"parallax":0.07,"scale":1.08},
        "layers":layers,"static_file":"production/magneto_soberano_metal_parallax.webp",
        "particles":[{"kind":"motes","params":{"count":16,"speed":0.10,"color":"#FF62D8","min_size":1.0,"max_size":3.0}}],
        "cycles":cycles,"sprites":[],
        "title":{"es":"Magneto · Soberano del metal","en":"Magneto · Master of Metal"},
        "tags":["magneto","x-men","marvel","mutantes","metal","magnetismo","fan art","parallax"],
        "category_semantic":"comics","glow":"#FF62D8","name":"Magneto · Soberano del metal",
        "desc_plain":"Magneto domina una ciudad destruida mientras vigas y fragmentos orbitan dentro de su campo magnético.",
        "desc_rich":"[[name:Magneto]], conocido como Max Eisenhardt, debutó en [[work:X-Men #1]] (1963), creado por [[creator:Stan Lee]] y [[creator:Jack Kirby]]. Controla campos magnéticos, manipula metal, crea barreras, vuela y genera pulsos electromagnéticos. Su conflicto con Charles Xavier representa dos respuestas distintas ante la persecución de los mutantes. En esta escena flota sobre una ciudad devastada mientras vigas, escombros y ondas rosadas responden a su voluntad.",
        "featured":False,"published":False,
    })
    # Completar vocabulario que el uploader compartido antiguo no conserva.
    spec=get_json(SCENES_BUCKET,f"{SID}.json")
    by_key={x["key"]:x for x in spec["image_layers"]}
    by_key["metal_far"]["drift"]=far_drift
    by_key["metal_near"]["drift"]=near_drift
    for i in range(3):
        p=by_key[f"magnetic_pulse_{i}"]
        p["initial_alpha"]=1.0 if i==0 else 0.0
        p["bob_phase_source"]="magneto_fullbody"
    spec["published"]=False
    put_json(SCENES_BUCKET,f"{SID}.json",spec)
    cat=get_json(IMG_BUCKET,"catalog_index.json")
    entry=next(x for x in cat["items"] if x.get("id")==SID)
    entry.setdefault("created_at",datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    entry["published"]=False
    cat["version"] = int(cat.get("version",0) or 0)+1
    put_json(IMG_BUCKET,"catalog_index.json",cat)
    print(result)
