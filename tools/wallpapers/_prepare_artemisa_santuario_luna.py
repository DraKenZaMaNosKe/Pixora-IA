"""Prepara las capas de Artemisa: Santuario de la Luna."""
from __future__ import annotations
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/artemisa_santuario_luna_20260820")
TARGET = (1080, 2340)
BG_OVERSCAN = (1200, 2600)

def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    src = image.convert("RGB")
    scale = max(size[0] / src.width, size[1] / src.height)
    resized = src.resize((round(src.width * scale), round(src.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - size[0]) // 2; top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))

def resize_rgba(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32)
    alpha = rgba[:, :, 3:4] / 255.0
    premul = rgba[:, :, :3] * alpha
    channels = [np.asarray(Image.fromarray(premul[:, :, i].astype("uint8"), "L").resize(size, Image.Resampling.LANCZOS), dtype=np.float32) for i in range(3)]
    alpha_out = np.asarray(Image.fromarray(rgba[:, :, 3].astype("uint8"), "L").resize(size, Image.Resampling.LANCZOS), dtype=np.float32)
    safe = np.maximum(alpha_out[:, :, None] / 255.0, 1.0 / 255.0)
    rgb = np.clip(np.stack(channels, axis=2) / safe, 0, 255)
    out = np.dstack([rgb, alpha_out]).astype("uint8"); out[alpha_out == 0, :3] = 0
    return Image.fromarray(out, "RGBA")

def main() -> None:
    background = cover(Image.open(ROOT / "source/artemis_background_original.png"), BG_OVERSCAN)
    background.save(ROOT / "parallax/layers/background.png")
    cutout = resize_rgba(Image.open(ROOT / "source/artemis_character_alpha.png"), (900, 1350))
    character = Image.new("RGBA", TARGET, (0, 0, 0, 0)); character.alpha_composite(cutout, (90, 760))
    character.save(ROOT / "parallax/layers/artemis_and_doe.png")

    # Resplandor lunar deliberado: diadema y arco, sin lavar cuerpo ni cierva.
    mask = Image.new("L", TARGET, 0); draw = ImageDraw.Draw(mask)
    draw.ellipse((515, 820, 610, 915), fill=150)
    draw.arc((690, 900, 1010, 1640), 262, 98, fill=145, width=13)
    glow = mask.filter(ImageFilter.GaussianBlur(10))
    aura = Image.new("RGBA", TARGET, (184, 214, 255, 0)); aura.putalpha(glow.point(lambda v: min(92, v)))
    aura.save(ROOT / "parallax/layers/moon_aura.png")

    flat = Image.alpha_composite(cover(background, TARGET).convert("RGBA"), aura)
    flat = Image.alpha_composite(flat, character).convert("RGB")
    flat.save(ROOT / "static/artemisa_santuario_luna_wallpaper.png", quality=96)
    flat.save(ROOT / "parallax/preview/artemisa_santuario_luna_preview.png", quality=94)
    (ROOT / "PREPARATION_REPORT.json").write_text(json.dumps({
        "target": list(TARGET), "background_overscan": list(BG_OVERSCAN),
        "character_size": [900, 1350], "character_xy": [90, 760],
        "layers": ["background", "moon_aura", "artemis_and_doe"], "source_preserved": True,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__": main()
