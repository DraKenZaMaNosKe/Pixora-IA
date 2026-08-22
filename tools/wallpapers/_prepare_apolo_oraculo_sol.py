"""Prepara las capas de Apolo: Oráculo del Sol."""
from __future__ import annotations
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/apolo_oraculo_sol_20260820")
TARGET = (1080, 2340)
BG_OVERSCAN = (1200, 2600)

def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    src = image.convert("RGB")
    scale = max(size[0] / src.width, size[1] / src.height)
    resized = src.resize((round(src.width * scale), round(src.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))

def resize_rgba(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32)
    alpha = rgba[:, :, 3:4] / 255.0
    premul = rgba[:, :, :3] * alpha
    channels = [np.asarray(Image.fromarray(premul[:, :, i].astype("uint8"), "L").resize(size, Image.Resampling.LANCZOS), dtype=np.float32) for i in range(3)]
    alpha_out = np.asarray(Image.fromarray(rgba[:, :, 3].astype("uint8"), "L").resize(size, Image.Resampling.LANCZOS), dtype=np.float32)
    safe = np.maximum(alpha_out[:, :, None] / 255.0, 1.0 / 255.0)
    rgb = np.clip(np.stack(channels, axis=2) / safe, 0, 255)
    out = np.dstack([rgb, alpha_out]).astype("uint8")
    out[alpha_out == 0, :3] = 0
    return Image.fromarray(out, "RGBA")

def main() -> None:
    for p in (ROOT / "parallax/layers", ROOT / "parallax/preview", ROOT / "static"):
        p.mkdir(parents=True, exist_ok=True)
    background = cover(Image.open(ROOT / "source/apolo_background_original.png"), BG_OVERSCAN)
    background.save(ROOT / "parallax/layers/background.png")

    cutout = resize_rgba(Image.open(ROOT / "source/apolo_character_alpha.png"), (930, 1640))
    character = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    character.alpha_composite(cutout, (75, 620))
    character.save(ROOT / "parallax/layers/apollo_full.png")

    # Pulso solar localizado: lira, corona de laurel y arco; evita lavar el cuerpo.
    mask = Image.new("L", TARGET, 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((55, 1010, 355, 1430), fill=120)     # lira y cuerdas
    draw.ellipse((300, 650, 565, 925), fill=70)       # laurel y cabello superior
    draw.line((790, 790, 935, 1770), fill=68, width=18)  # arco
    glow = mask.filter(ImageFilter.GaussianBlur(13))
    aura = Image.new("RGBA", TARGET, (255, 210, 94, 0))
    aura.putalpha(glow.point(lambda v: min(84, v)))
    aura.save(ROOT / "parallax/layers/solar_aura.png")

    flat = Image.alpha_composite(cover(background, TARGET).convert("RGBA"), aura)
    flat = Image.alpha_composite(flat, character).convert("RGB")
    flat.save(ROOT / "static/apolo_oraculo_sol_wallpaper.png", quality=96)
    flat.save(ROOT / "parallax/preview/apolo_oraculo_sol_preview.png", quality=94)
    (ROOT / "PREPARATION_REPORT.json").write_text(json.dumps({
        "target": list(TARGET), "background_overscan": list(BG_OVERSCAN),
        "character_size": [930, 1640], "character_xy": [75, 620],
        "layers": ["background", "solar_aura", "apollo_full"],
        "effect": "pulso dorado localizado en lira, laurel y arco",
        "source_preserved": True,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    main()
