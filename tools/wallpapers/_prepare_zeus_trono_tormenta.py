"""Prepara capas y preview de Zeus: Trono de la tormenta."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/zeus_trono_tormenta_20260820")
SRC = ROOT / "source"
LAYERS = ROOT / "parallax" / "layers"
STATIC = ROOT / "static"
PREVIEW = ROOT / "preview"
for folder in (LAYERS, STATIC, PREVIEW):
    folder.mkdir(parents=True, exist_ok=True)


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def resize_rgba_premultiplied(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Escala alpha sin mezclar el RGB oculto del antiguo chroma en el borde."""
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32)
    alpha = rgba[:, :, 3:4] / 255.0
    premul = rgba[:, :, :3] * alpha
    channels = [
        np.asarray(Image.fromarray(premul[:, :, i].astype("uint8"), "L").resize(size, Image.Resampling.LANCZOS), dtype=np.float32)
        for i in range(3)
    ]
    alpha_out = np.asarray(
        Image.fromarray(rgba[:, :, 3].astype("uint8"), "L").resize(size, Image.Resampling.LANCZOS),
        dtype=np.float32,
    )
    rgb_premul = np.stack(channels, axis=2)
    safe_alpha = np.maximum(alpha_out[:, :, None] / 255.0, 1.0 / 255.0)
    rgb = np.clip(rgb_premul / safe_alpha, 0, 255)
    out = np.dstack([rgb, alpha_out]).astype("uint8")
    out[alpha_out == 0, :3] = 0
    return Image.fromarray(out, "RGBA")


background = cover(Image.open(SRC / "zeus_background_generated.png").convert("RGB"), (1200, 2600))
background.save(LAYERS / "background.png", optimize=True)

zeus_src = Image.open(SRC / "zeus_character_alpha.png").convert("RGBA")
target_w = 930
target_h = round(zeus_src.height * target_w / zeus_src.width)
zeus_scaled = resize_rgba_premultiplied(zeus_src, (target_w, target_h))
zeus_canvas = Image.new("RGBA", (1080, 2340), (0, 0, 0, 0))
zx = (1080 - target_w) // 2
zy = 650
zeus_canvas.alpha_composite(zeus_scaled, (zx, zy))
zeus_canvas.save(LAYERS / "zeus_full.png", optimize=True)

# Resplandor exclusivo del rayo: se limita al cuadrante superior izquierdo
# para no convertir toda la armadura dorada en una mancha luminosa.
arr = np.asarray(zeus_canvas)
rgb = arr[:, :, :3]
alpha = arr[:, :, 3]
yy, xx = np.indices(alpha.shape)
bright = (rgb.max(axis=2) > 225) & (rgb[:, :, 0] > 190) & (rgb[:, :, 1] > 150)
region = (xx < 525) & (yy < 1120)
mask = np.where(bright & region & (alpha > 20), 220, 0).astype("uint8")
mask_img = Image.fromarray(mask, "L").filter(ImageFilter.GaussianBlur(28))
glow = Image.new("RGBA", zeus_canvas.size, (255, 202, 75, 0))
glow.putalpha(mask_img)
glow.save(LAYERS / "lightning_aura.png", optimize=True)

# Flat preview 1080x2340 using the same geometry as the renderer.
bg_flat = cover(background, (1080, 2340)).convert("RGBA")
bg_flat.alpha_composite(glow)
bg_flat.alpha_composite(zeus_canvas)
flat = bg_flat.convert("RGB")
flat.save(STATIC / "zeus_trono_tormenta_wallpaper.png", optimize=True)
flat.save(PREVIEW / "zeus_trono_tormenta_preview.png", optimize=True)

report = {
    "scene_id": "zeus_trono_tormenta",
    "background": {"size": list(background.size)},
    "zeus": {"size": list(zeus_canvas.size), "source_size": list(zeus_src.size), "placement": [zx, zy], "target_size": [target_w, target_h]},
    "lightning_aura": {"size": list(glow.size), "alpha_bbox": list(glow.getchannel("A").getbbox() or ())},
    "static": {"size": list(flat.size)},
}
(ROOT / "PREPARATION_REPORT.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))
