"""Prepara el sprite alineado del gatito curioso para QA."""
from __future__ import annotations

import json
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_curioso_parpadeo_20260812")


def main() -> None:
    layers = ROOT / "parallax" / "layers"
    frames_dir = ROOT / "parallax" / "frames"
    production = ROOT / "production"
    frames_dir.mkdir(parents=True, exist_ok=True)
    production.mkdir(parents=True, exist_ok=True)

    poses = {name: Image.open(layers / f"full_{name}.png").convert("RGBA")
             for name in ("eyes_open", "eyes_half", "eyes_closed", "surprised")}
    # Full-body sheet has no wall. Align every pose by its non-transparent
    # bounding box and feet baseline so only the expression changes.
    boxes = {name: im.getbbox() for name, im in poses.items()}
    canvas = (max(box[2] - box[0] for box in boxes.values()),
              max(box[3] - box[1] for box in boxes.values()))
    aligned = {}
    for name, im in poses.items():
        out = Image.new("RGBA", canvas, (0, 0, 0, 0))
        box = boxes[name]
        cat_only = im.crop(box)
        out.alpha_composite(cat_only, ((canvas[0] - cat_only.width) // 2,
                                       canvas[1] - cat_only.height))
        aligned[name] = out

    # Una pose visible por frame. La pausa larga vive en frame_skip del renderer.
    sequence = ["eyes_open", "eyes_half", "eyes_closed", "eyes_half",
                "eyes_open", "eyes_open", "surprised", "eyes_open"]
    for old in frames_dir.glob("frame_*.png"):
        old.unlink()
    for index, name in enumerate(sequence, 1):
        aligned[name].save(frames_dir / f"frame_{index:03d}.png", optimize=True)

    pack = production / "gatito_curioso_parpadeo_sprite.zip"
    with zipfile.ZipFile(pack, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for frame in sorted(frames_dir.glob("frame_*.png")):
            zf.write(frame, frame.name)

    report = {"scene_id": "gatito_curioso_parpadeo", "canvas": list(canvas),
              "frames": len(sequence), "sequence": sequence,
              "full_body": True, "removed_sprite_wall": True,
              "sprite_zip_bytes": pack.stat().st_size}
    (ROOT / "PREPARATION_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
