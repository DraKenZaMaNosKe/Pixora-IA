"""Prepara assets 1080x2340 para El aquelarre de los nueve bigotes."""
from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/aquelarre_nueve_bigotes_parallax")
SRC = ROOT / "source/aquelarre_master_imagegen.png"
LAYERS = ROOT / "layers"
PROD = ROOT / "production"
QA = ROOT / "qa"
TARGET = (1080, 2340)


def fit_master() -> Image.Image:
    src = Image.open(SRC).convert("RGB")
    scale = min(TARGET[0] / src.width, TARGET[1] / src.height)
    resized = src.resize((round(src.width * scale), round(src.height * scale)), Image.Resampling.LANCZOS)
    out = Image.new("RGB", TARGET, (0, 0, 0))
    out.paste(resized, ((TARGET[0] - resized.width) // 2, (TARGET[1] - resized.height) // 2))
    return out


def glow_layer(mask: np.ndarray, color: tuple[int, int, int], blur: float, opacity: float) -> Image.Image:
    a = cv2.GaussianBlur(mask, (0, 0), blur)
    rgba = np.zeros((TARGET[1], TARGET[0], 4), dtype=np.uint8)
    rgba[:, :, :3] = color
    rgba[:, :, 3] = np.clip(a.astype(np.float32) * opacity, 0, 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def main() -> None:
    LAYERS.mkdir(parents=True, exist_ok=True)
    PROD.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    master = fit_master()
    master.save(LAYERS / "background_master.png", optimize=True)
    master.save(PROD / "aquelarre_nueve_bigotes.webp", "WEBP", quality=94, method=6)
    preview = master.copy(); preview.thumbnail((540, 1170), Image.Resampling.LANCZOS)
    preview.save(PROD / "preview.jpg", quality=91, optimize=True)

    arr = np.array(master)
    hsv = cv2.cvtColor(arr, cv2.COLOR_RGB2HSV)
    red = ((((hsv[:, :, 0] <= 8) | (hsv[:, :, 0] >= 174)) &
            (hsv[:, :, 1] >= 145) & (hsv[:, :, 2] >= 110)).astype(np.uint8) * 255)

    # Tres intensidades del fuego/runa: el grabado original queda intacto y
    # solo su halo respira, evitando deformaciones entre fotogramas.
    for index, (blur, opacity) in enumerate(((4.0, 0.26), (8.0, 0.42), (13.0, 0.58))):
        glow_layer(red, (255, 35, 20), blur, opacity).save(LAYERS / f"scarlet_glow_{index}.png", optimize=True)

    # Ojos: máscaras extraídas de los píxeles marfil originales. Esto mantiene
    # cada brillo exactamente dentro del dibujo, incluso tras el cover-fit.
    ivory = ((hsv[:, :, 1] < 100) & (hsv[:, :, 2] > 130)).astype(np.uint8) * 255
    eye_boxes = [
        (239, 1036, 291, 1061), (333, 1032, 374, 1059),
        (461, 933, 514, 969), (556, 939, 612, 973),
        (704, 1036, 745, 1064), (787, 1051, 837, 1076),
    ]
    open_mask = np.zeros((TARGET[1], TARGET[0]), dtype=np.uint8)
    for x0, y0, x1, y1 in eye_boxes:
        open_mask[y0:y1, x0:x1] = ivory[y0:y1, x0:x1]
    for index, squeeze in enumerate((1.0, 0.45, 0.12)):
        state = np.zeros_like(open_mask)
        for x0, y0, x1, y1 in eye_boxes:
            crop = Image.fromarray(open_mask[y0:y1, x0:x1], "L")
            nh = max(1, round(crop.height * squeeze))
            crop = crop.resize((crop.width, nh), Image.Resampling.LANCZOS)
            cy = (y0 + y1) // 2
            top = cy - nh // 2
            state[top:top+nh, x0:x1] = np.maximum(state[top:top+nh, x0:x1], np.array(crop))
        core = glow_layer(state, (255, 238, 152), 1.2, 0.78)
        halo = glow_layer(state, (255, 58, 28), 5.0, 0.30)
        core = Image.alpha_composite(halo, core)
        core.save(LAYERS / f"eyes_{index}.png", optimize=True)

    # Velas: cuatro halos independientes reunidos en una capa ligera.
    candles = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    cd = ImageDraw.Draw(candles, "RGBA")
    for x, y, radius in ((45, 1660, 62), (1030, 1660, 62), (155, 1925, 72), (890, 1925, 72)):
        cd.ellipse((x-radius, y-radius, x+radius, y+radius), fill=(255, 55, 25, 70))
        cd.ellipse((x-18, y-28, x+18, y+28), fill=(255, 224, 130, 190))
    candles.filter(ImageFilter.GaussianBlur(18)).save(LAYERS / "candle_auras.png", optimize=True)

    # Libro: halo marfil muy tenue, como tinta que despierta.
    book = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    bd = ImageDraw.Draw(book, "RGBA")
    bd.ellipse((260, 1370, 820, 1785), fill=(255, 228, 166, 45))
    book.filter(ImageFilter.GaussianBlur(34)).save(LAYERS / "book_aura.png", optimize=True)

    report = {
        "scene_id": "aquelarre_nueve_bigotes_parallax",
        "master_size": list(TARGET),
        "layers": [p.name for p in sorted(LAYERS.glob("*.png"))],
        "source": str(SRC),
        "imagegen_prompt_mode": "style-transfer from user reference",
    }
    (ROOT / "PREPARATION_REPORT.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ROOT / "METADATA_DESCRIPCION.md").write_text(
        "# El aquelarre de los nueve bigotes\n\n"
        "Escena original de fantasía gótica inspirada en grabados y carteles de tinta limitada. "
        "Tres gatos de expresiones solemnes vigilan un libro de símbolos inventados mientras las velas, "
        "las llamas y una luna roja convierten la reunión en un ritual teatral y humorístico.\n\n"
        "Los personajes no pertenecen a una película o anime conocido: son arquetipos originales. "
        "El gato negro central funciona como guardián del libro; el tuxedo de la izquierda parece el "
        "escéptico del grupo y el atigrado de la derecha aporta una expresión cansada y cómica. "
        "Los signos son decorativos y ficticios; no reproducen instrucciones rituales reales.\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
