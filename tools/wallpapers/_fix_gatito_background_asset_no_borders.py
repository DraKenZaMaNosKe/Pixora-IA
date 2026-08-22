"""Reemplaza el fondo por una pared continua sin molduras negras laterales."""
from __future__ import annotations

import io
import json
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw

from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put, put_json


SID = "gatito_resbalon_pared"
ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/gatito_resbalon_pared")


def webp(im: Image.Image, quality: int) -> bytes:
    buf = io.BytesIO()
    im.save(buf, "WEBP", quality=quality, method=6)
    return buf.getvalue()


def main() -> None:
    spec = get_json(SCENES_BUCKET, f"{SID}.json")
    if spec.get("published") is not False:
        raise RuntimeError("La escena ya no es privada")
    sprites_before = json.loads(json.dumps(spec.get("sprites", [])))
    bg_layers = [layer for layer in spec.get("image_layers", []) if layer.get("key") == "background"]
    if len(bg_layers) != 1:
        raise RuntimeError(f"Fondos encontrados: {len(bg_layers)}")

    bg = Image.new("RGB", (1080, 2340), "#F6AA35")
    draw = ImageDraw.Draw(bg)
    for x in range(0, 1080, 90):
        shade = "#F3A331" if (x // 90) % 2 == 0 else "#F8B13D"
        draw.rectangle((x, 0, min(1079, x + 44), 2339), fill=shade)

    # Pistas visuales discretas de que es una pared, sin robar protagonismo.
    ink = "#B86B2A"
    ink_soft = "#D4872E"
    # Grietas finas cerca de la zona de escalada.
    draw.line([(866, 640), (839, 683), (859, 710), (823, 754)], fill=ink, width=7)
    draw.line([(839, 683), (801, 674), (776, 695)], fill=ink_soft, width=5)
    draw.line([(859, 710), (897, 730), (916, 764)], fill=ink_soft, width=5)
    # Zocalo: suficiente contraste para explicar la pared, sin borde negro.
    draw.rectangle((0, 2040, 1079, 2062), fill="#CE7A29")
    draw.rectangle((0, 2063, 1079, 2339), fill="#E9902F")
    draw.line([(0, 2080), (1079, 2080)], fill="#F4AF49", width=6)
    # Agujero de raton y dos ojos curiosos: pequeño remate comico.
    # La base del hueco coincide con el zocalo: el raton no puede "flotar".
    draw.pieslice((808, 1955, 1000, 2167), 180, 360, fill="#7A472B")
    draw.ellipse((870, 2027, 884, 2046), fill="#FFE7A6")
    draw.ellipse((909, 2027, 923, 2046), fill="#FFE7A6")
    draw.arc((920, 2045, 1025, 2125), 160, 285, fill="#7A472B", width=8)
    bg_path = ROOT / "production" / "background.png"
    bg.save(bg_path, optimize=True)
    body = webp(bg, 92)
    put(IMG_BUCKET, f"{SID}_background.webp", body)

    # Portada coherente con el tamaño grande aprobado en el editor.
    flat = bg.convert("RGBA")
    hero = Image.open(ROOT / "poses" / "pose_1.png").convert("RGBA")
    hero = hero.resize((int(hero.width * 3.45), int(hero.height * 3.45)), Image.Resampling.LANCZOS)
    flat.alpha_composite(hero, (659 - hero.width // 2, 650))
    flat_rgb = flat.convert("RGB")
    flat_body = webp(flat_rgb, 90)
    preview = flat_rgb.copy()
    preview.thumbnail((540, 1170), Image.Resampling.LANCZOS)
    preview_body = webp(preview, 86)
    put(IMG_BUCKET, f"{SID}.webp", flat_body)
    put(IMG_BUCKET, f"{SID}_preview.webp", preview_body)
    flat_rgb.save(ROOT / "production" / "gatito_resbalon_flat.jpg", quality=94)

    bg_layers[0]["scale"] = 1.24
    bg_layers[0]["revision"] = int(bg_layers[0].get("revision", 1)) + 1
    put_json(SCENES_BUCKET, f"{SID}.json", spec)

    remote = get_json(SCENES_BUCKET, f"{SID}.json")
    remote_bg = next(layer for layer in remote["image_layers"] if layer.get("key") == "background")
    if remote.get("sprites") != sprites_before:
        raise RuntimeError("Se alteraron los ajustes del gatito")
    receipt = {
        "scene_id": SID,
        "fixed_at": datetime.now(timezone.utc).isoformat(),
        "background": "continuous striped orange wall with subtle cracks, baseboard and mouse-hole joke",
        "background_bytes": len(body),
        "flat_bytes": len(flat_body),
        "preview_bytes": len(preview_body),
        "background_scale": remote_bg.get("scale"),
        "background_revision": remote_bg.get("revision"),
        "sprite_preserved": remote.get("sprites"),
        "published": remote.get("published"),
    }
    (ROOT / "SCENE_SPEC_QA.json").write_text(
        json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (ROOT / "FIX_BACKGROUND_NO_BORDERS_RECEIPT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
