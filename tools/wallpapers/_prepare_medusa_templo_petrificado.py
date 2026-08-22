"""Prepara las capas maestras de Medusa sin tocar los originales generados."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter


ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/medusa_templo_petrificado_20260820")
TARGET = (1080, 2340)
BG_OVERSCAN = (1200, 2600)


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    src = image.convert("RGB")
    scale = max(size[0] / src.width, size[1] / src.height)
    resized = src.resize((round(src.width * scale), round(src.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def resize_rgba_premultiplied(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32)
    alpha = rgba[:, :, 3:4] / 255.0
    premul = rgba[:, :, :3] * alpha
    channels = [
        np.asarray(
            Image.fromarray(premul[:, :, index].astype("uint8"), "L").resize(size, Image.Resampling.LANCZOS),
            dtype=np.float32,
        )
        for index in range(3)
    ]
    alpha_out = np.asarray(
        Image.fromarray(rgba[:, :, 3].astype("uint8"), "L").resize(size, Image.Resampling.LANCZOS),
        dtype=np.float32,
    )
    safe_alpha = np.maximum(alpha_out[:, :, None] / 255.0, 1.0 / 255.0)
    rgb = np.clip(np.stack(channels, axis=2) / safe_alpha, 0, 255)
    out = np.dstack([rgb, alpha_out]).astype("uint8")
    out[alpha_out == 0, :3] = 0
    return Image.fromarray(out, "RGBA")


def main() -> None:
    bg_src = Image.open(ROOT / "source/medusa_background_generated.png")
    char_src = Image.open(ROOT / "source/medusa_character_generated.png").convert("RGBA")

    background = cover(bg_src, BG_OVERSCAN)
    background.save(ROOT / "parallax/layers/background.png")

    char = resize_rgba_premultiplied(char_src, (850, 1510))
    character = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    character.alpha_composite(char, (115, 520))
    character.save(ROOT / "parallax/layers/medusa_full.png")

    # Aura limitada a corona/serpientes y dos ojos explícitos. La ropa queda excluida.
    rgb = character.convert("RGB")
    r, g, b = rgb.split()
    green = ImageChops.subtract(g, ImageChops.lighter(r, b))
    green = green.point(lambda value: 255 if value > 20 else 0)
    head_region = Image.new("L", TARGET, 0)
    ImageDraw.Draw(head_region).rectangle((205, 500, 875, 790), fill=255)
    green = ImageChops.multiply(green, head_region)
    green = ImageChops.multiply(green, character.getchannel("A"))
    eyes = Image.new("L", TARGET, 0)
    eye_draw = ImageDraw.Draw(eyes)
    eye_draw.ellipse((487, 787, 532, 824), fill=255)
    eye_draw.ellipse((548, 787, 593, 824), fill=255)
    glow = ImageChops.lighter(green, eyes).filter(ImageFilter.GaussianBlur(10))
    glow = ImageEnhance.Brightness(glow).enhance(1.35)
    aura = Image.new("RGBA", TARGET, (66, 255, 185, 0))
    aura.putalpha(glow.point(lambda value: min(118, value)))
    aura.save(ROOT / "parallax/layers/emerald_gaze_aura.png")

    flat_bg = cover(background, TARGET).convert("RGBA")
    flat = Image.alpha_composite(flat_bg, aura)
    flat = Image.alpha_composite(flat, character).convert("RGB")
    flat.save(ROOT / "static/medusa_templo_petrificado_wallpaper.png", quality=96)
    flat.save(ROOT / "preview/medusa_templo_petrificado_preview.png", quality=94)

    report = {
        "target": list(TARGET),
        "background_overscan": list(BG_OVERSCAN),
        "character_size": [850, 1510],
        "character_xy": [115, 520],
        "layers": ["background", "emerald_gaze_aura", "medusa_full"],
        "source_preserved": True,
    }
    (ROOT / "PREPARATION_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
