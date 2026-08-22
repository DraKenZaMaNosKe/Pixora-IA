"""Amplia solo el fondo del Gatito, preservando los ajustes del editor."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from _upload_scene_generic import SCENES_BUCKET, get_json, put_json


SID = "gatito_resbalon_pared"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_resbalon_pared")


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    if spec.get("published") is not False:
        raise RuntimeError("La escena ya no es privada; se cancela el ajuste")
    backgrounds = [layer for layer in spec.get("image_layers", []) if layer.get("key") == "background"]
    if len(backgrounds) != 1:
        raise RuntimeError(f"Fondos encontrados: {len(backgrounds)}")
    sprites_before = json.loads(json.dumps(spec.get("sprites", [])))
    old_scale = float(backgrounds[0].get("scale", 1.0))
    backgrounds[0]["scale"] = 1.24
    put_json(SCENES_BUCKET, f"{SID}.json", spec)

    remote = get_json(SCENES_BUCKET, f"{SID}.json")
    remote_bg = next(layer for layer in remote["image_layers"] if layer.get("key") == "background")
    if abs(float(remote_bg["scale"]) - 1.24) > 0.0001:
        raise RuntimeError("La verificacion remota de escala fallo")
    if remote.get("sprites") != sprites_before:
        raise RuntimeError("El ajuste altero los cambios del editor en el gatito")

    receipt = {
        "scene_id": SID,
        "fixed_at": datetime.now(timezone.utc).isoformat(),
        "background_scale_before": old_scale,
        "background_scale_after": remote_bg["scale"],
        "sprite_preserved": remote.get("sprites"),
        "published": remote.get("published"),
    }
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "FIX_BACKGROUND_COVERAGE_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
