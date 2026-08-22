"""Prepara las capas de Perséfone: Entre Dos Reinos."""
from __future__ import annotations
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/persefone_dos_reinos_20260820")
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
    background = cover(Image.open(ROOT / "source/persephone_background_original.png"), BG_OVERSCAN)
    background.save(ROOT / "parallax/layers/background.png")
    cutout = resize_rgba(Image.open(ROOT / "source/persephone_character_alpha.png"), (840, 1480))
    character = Image.new("RGBA", TARGET, (0, 0, 0, 0)); character.alpha_composite(cutout, (120, 690))
    character.save(ROOT / "parallax/layers/persephone_full.png")

    # Dos energías deliberadas: violeta alrededor de la granada/inframundo y
    # oro floral alrededor de la primavera. Permanecen en una sola capa para
    # que ambas viajen exactamente junto con Perséfone.
    under_mask = Image.new("L", TARGET, 0); under_draw = ImageDraw.Draw(under_mask)
    under_draw.ellipse((120, 930, 520, 1420), fill=140)
    spring_mask = Image.new("L", TARGET, 0); spring_draw = ImageDraw.Draw(spring_mask)
    spring_draw.ellipse((560, 930, 980, 1480), fill=135)
    under_glow = under_mask.filter(ImageFilter.GaussianBlur(10)).point(lambda v: min(86, v))
    spring_glow = spring_mask.filter(ImageFilter.GaussianBlur(10)).point(lambda v: min(82, v))
    under_aura = Image.new("RGBA", TARGET, (190, 124, 255, 0)); under_aura.putalpha(under_glow)
    spring_aura = Image.new("RGBA", TARGET, (255, 216, 112, 0)); spring_aura.putalpha(spring_glow)
    aura = Image.alpha_composite(under_aura, spring_aura)
    aura.save(ROOT / "parallax/layers/dual_aura.png")

    flat = Image.alpha_composite(cover(background, TARGET).convert("RGBA"), aura)
    flat = Image.alpha_composite(flat, character).convert("RGB")
    flat.save(ROOT / "static/persefone_dos_reinos_wallpaper.png", quality=96)
    flat.save(ROOT / "parallax/preview/persefone_dos_reinos_preview.png", quality=94)
    (ROOT / "PREPARATION_REPORT.json").write_text(json.dumps({
        "target": list(TARGET), "background_overscan": list(BG_OVERSCAN),
        "character_size": [840, 1480], "character_xy": [120, 690],
        "layers": ["background", "dual_aura", "persephone_full"], "source_preserved": True,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__": main()


