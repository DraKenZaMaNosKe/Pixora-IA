"""Prepara capas Pixora de la rana psicodélica sobre loto."""
from pathlib import Path
from PIL import Image, ImageFilter

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/rana_psicodelica_loto_20260822")


def cover(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    ratio = max(size[0] / im.width, size[1] / im.height)
    scaled = im.resize((round(im.width * ratio), round(im.height * ratio)), Image.Resampling.LANCZOS)
    left = (scaled.width - size[0]) // 2
    top = (scaled.height - size[1]) // 2
    return scaled.crop((left, top, left + size[0], top + size[1]))


def main() -> None:
    bg_src = Image.open(ROOT / "source/background_clean.png").convert("RGB")
    subject_src = Image.open(ROOT / "parallax/layers/frog_lotus_alpha_final.png").convert("RGBA")
    bbox = subject_src.getchannel("A").getbbox()
    if not bbox:
        raise RuntimeError("La capa rana+loto está vacía")
    subject = subject_src.crop(bbox)
    width = 920
    subject = subject.resize((width, round(subject.height * width / subject.width)), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (1080, 2340), (0, 0, 0, 0))
    x = (1080 - subject.width) // 2
    y = 2210 - subject.height
    canvas.alpha_composite(subject, (x, y))
    canvas.save(ROOT / "parallax/layers/frog_lotus_canvas.png", optimize=True)

    background = cover(bg_src, (1200, 2600))
    background.save(ROOT / "parallax/layers/background.png", optimize=True)
    preview = cover(bg_src, (1080, 2340)).convert("RGBA")
    preview.alpha_composite(canvas)
    preview.convert("RGB").save(ROOT / "preview/preview.png", optimize=True)
    preview.convert("RGB").save(ROOT / "static/wallpaper_static.png", optimize=True)

    alpha = canvas.getchannel("A").filter(ImageFilter.GaussianBlur(24))
    aura = Image.new("RGBA", canvas.size, (50, 245, 220, 0))
    aura.putalpha(alpha.point(lambda p: min(72, p // 4)))
    aura.save(ROOT / "parallax/layers/bioluminescent_aura.png", optimize=True)


if __name__ == "__main__":
    main()
