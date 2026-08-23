"""Prepare two selected cloud-traveler concepts as Pixora canvas layers."""
from pathlib import Path
from PIL import Image, ImageFilter

BASE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar")
CASES = {
    "viajero_sendero_luna_20260821": {"layer": "traveler_full.png", "width": 500, "center": (805, 1910)},
    "viajero_portal_estelar_20260821": {"layer": "traveler_star_full.png", "width": 500, "center": (315, 1685)},
}


def cover(source: Image.Image, size: tuple[int, int]) -> Image.Image:
    ratio = max(size[0] / source.width, size[1] / source.height)
    scaled = source.resize((round(source.width * ratio), round(source.height * ratio)), Image.Resampling.LANCZOS)
    left = (scaled.width - size[0]) // 2
    top = (scaled.height - size[1]) // 2
    return scaled.crop((left, top, left + size[0], top + size[1]))


def fitted_sprite(source: Image.Image, width: int) -> Image.Image:
    alpha = source.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        raise RuntimeError("Sprite vacío")
    crop = source.crop(bbox)
    height = round(crop.height * width / crop.width)
    return crop.resize((width, height), Image.Resampling.LANCZOS)


def main() -> None:
    for folder, cfg in CASES.items():
        root = BASE / folder
        background_source = Image.open(root / "source/background_clean.png").convert("RGB")
        composite_source = Image.open(root / "source/composite.png").convert("RGB")
        sprite_source = Image.open(root / "parallax/layers" / cfg["layer"]).convert("RGBA")

        background = cover(background_source, (1200, 2600))
        background.save(root / "parallax/layers/background.png", optimize=True)
        flat = cover(composite_source, (1080, 2340))
        flat.save(root / "static/wallpaper_static.png", optimize=True)

        sprite = fitted_sprite(sprite_source, cfg["width"])
        canvas = Image.new("RGBA", (1080, 2340), (0, 0, 0, 0))
        x = round(cfg["center"][0] - sprite.width / 2)
        y = round(cfg["center"][1] - sprite.height / 2)
        canvas.alpha_composite(sprite, (x, y))
        canvas.save(root / "parallax/layers/traveler_canvas.png", optimize=True)

        preview = cover(background_source, (1080, 2340)).convert("RGBA")
        preview.alpha_composite(canvas)
        preview.convert("RGB").save(root / "preview/preview.png", optimize=True)

        glow = canvas.getchannel("A").filter(ImageFilter.GaussianBlur(22))
        aura = Image.new("RGBA", canvas.size, (120, 220, 255, 0))
        aura.putalpha(glow.point(lambda p: min(70, p // 4)))
        aura.save(root / "parallax/layers/traveler_aura.png", optimize=True)
        print(folder, "sprite", sprite.size, "at", (x, y))


if __name__ == "__main__":
    main()
