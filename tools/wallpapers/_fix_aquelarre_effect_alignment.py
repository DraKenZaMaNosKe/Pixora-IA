"""Ancla los efectos del aquelarre al grabado base sin republicar la escena."""
from pathlib import Path
import json

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json


SID = "aquelarre_nueve_bigotes_parallax"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/aquelarre_nueve_bigotes_parallax")


if __name__ == "__main__":
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    shared_drift = {"amp_x_pct": 0.16, "amp_y_pct": -0.10, "scale_min": 1.0, "scale_max": 1.012, "rot_deg": 0.08, "period_s": 30.0}
    for layer in spec.get("image_layers", []):
        layer["parallax_factor"] = 0.10
        layer["scale"] = 1.24
        layer["drift"] = shared_drift
    spec["published"] = False
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print({"scene_id": SID, "layers_aligned": len(spec.get("image_layers", [])), "published": spec.get("published")})
