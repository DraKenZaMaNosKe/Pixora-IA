"""Prepara las capas de Ares: Forja del Eclipse preservando los originales."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter


ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/ares_forja_eclipse_20260820")
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
    bg_src = Image.open(ROOT / "source/ares_forge_background_original.png")
    char_src = Image.open(ROOT / "source/ares_character_alpha_v2.png").convert("RGBA")

    background = cover(bg_src, BG_OVERSCAN)
    background.save(ROOT / "parallax/layers/background.png")

    char = resize_rgba_premultiplied(char_src, (930, 1395))
    character = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    character.alpha_composite(char, (75, 760))
    character.save(ROOT / "parallax/layers/ares_full.png")

    # Aura de metal caliente: naranja luminoso, no telas rojas ni penacho.
    rgba = np.asarray(character, dtype=np.uint8)
    rr = rgba[:, :, 0].astype(np.int16)
    gg = rgba[:, :, 1].astype(np.int16)
    bb = rgba[:, :, 2].astype(np.int16)
    aa = rgba[:, :, 3]
    hot = (
        (rr >= 145)
        & (gg >= 38)
        & (gg <= 178)
        & (rr - gg >= 32)
        & (gg - bb >= 4)
        & (aa >= 48)
    )
    # Excluye explícitamente el penacho; añade ambos ojos como focos controlados.
    hot[:1045, :] = False
    mask_array = np.where(hot, aa, 0).astype(np.uint8)
    mask_array[1082:1100, 535:555] = np.maximum(mask_array[1082:1100, 535:555], 205)
    mask_array[1082:1100, 565:585] = np.maximum(mask_array[1082:1100, 565:585], 205)
    red = Image.fromarray(mask_array, "L")
    glow = red.filter(ImageFilter.GaussianBlur(7))
    glow = ImageEnhance.Brightness(glow).enhance(1.15)
    aura = Image.new("RGBA", TARGET, (255, 62, 18, 0))
    aura.putalpha(glow.point(lambda value: min(105, value)))
    aura.save(ROOT / "parallax/layers/forge_aura.png")

    flat_bg = cover(background, TARGET).convert("RGBA")
    flat = Image.alpha_composite(flat_bg, aura)
    flat = Image.alpha_composite(flat, character).convert("RGB")
    flat.save(ROOT / "static/ares_forja_eclipse_wallpaper.png", quality=96)
    flat.save(ROOT / "parallax/preview/ares_forja_eclipse_preview.png", quality=94)

    report = {
        "target": list(TARGET),
        "background_overscan": list(BG_OVERSCAN),
        "character_size": [930, 1395],
        "character_xy": [75, 760],
        "layers": ["background", "forge_aura", "ares_full"],
        "source_preserved": True,
    }
    (ROOT / "PREPARATION_REPORT.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
