"""Ajusta el gato a un tamaño grande moderado antes de publicar."""
from __future__ import annotations

import json
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json


SID = "gatito_resbalon_pared"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_resbalon_pared")
TARGET_SCALE = 0.00520


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    if spec.get("published") is not False:
        raise RuntimeError("La escena ya no es privada")
    sprites = spec.get("sprites", [])
    if len(sprites) != 1 or sprites[0].get("manifest_key") != "gatito_resbalon_pared_gato":
        raise RuntimeError("Inventario de sprites inesperado")
    before = float(sprites[0]["params"].get("scale", 0))
    sprites[0]["params"]["scale"] = TARGET_SCALE
    put_json(SCENES_BUCKET, f"{SID}.json", spec)
    remote = get_json(SCENES_BUCKET, f"{SID}.json")
    after = float(remote["sprites"][0]["params"]["scale"])
    if abs(after - TARGET_SCALE) > 0.000001:
        raise RuntimeError("La verificacion remota de escala fallo")
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"scene_id": SID, "scale_before": before, "scale_after": after,
                      "published": remote.get("published")}, indent=2))


if __name__ == "__main__":
    main()
