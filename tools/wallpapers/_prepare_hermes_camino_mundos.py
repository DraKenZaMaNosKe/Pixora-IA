"""Prepara las capas de Hermes: Camino entre Mundos."""
from __future__ import annotations
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/hermes_camino_mundos_20260820")
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
    background = cover(Image.open(ROOT / "source/hermes_background_original.png"), BG_OVERSCAN)
    background.save(ROOT / "parallax/layers/background.png")
    cutout = resize_rgba(Image.open(ROOT / "source/hermes_character_alpha.png"), (880, 1440))
    character = Image.new("RGBA", TARGET, (0, 0, 0, 0)); character.alpha_composite(cutout, (100, 720))
    character.save(ROOT / "parallax/layers/hermes_full.png")

    # Resplandor lunar deliberado: sandalias aladas y caduceo, sin lavar el cuerpo.
    mask = Image.new("L", TARGET, 0); draw = ImageDraw.Draw(mask)
    # Caduceo completo: cabeza alada, vara y serpientes del lado izquierdo.
    draw.ellipse((185, 860, 390, 1135), fill=145)
    draw.line((285, 920, 315, 1910), fill=125, width=12)
    # Dos focos pequeños en las sandalias aladas, sin lavar la plataforma.
    draw.ellipse((250, 1950, 475, 2160), fill=135)
    draw.ellipse((560, 1950, 790, 2165), fill=135)
    glow = mask.filter(ImageFilter.GaussianBlur(10))
    aura = Image.new("RGBA", TARGET, (255, 214, 112, 0)); aura.putalpha(glow.point(lambda v: min(86, v)))
    aura.save(ROOT / "parallax/layers/speed_aura.png")

    flat = Image.alpha_composite(cover(background, TARGET).convert("RGBA"), aura)
    flat = Image.alpha_composite(flat, character).convert("RGB")
    flat.save(ROOT / "static/hermes_camino_mundos_wallpaper.png", quality=96)
    flat.save(ROOT / "parallax/preview/hermes_camino_mundos_preview.png", quality=94)
    (ROOT / "PREPARATION_REPORT.json").write_text(json.dumps({
        "target": list(TARGET), "background_overscan": list(BG_OVERSCAN),
        "character_size": [880, 1440], "character_xy": [100, 720],
        "layers": ["background", "speed_aura", "hermes_full"], "source_preserved": True,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__": main()

