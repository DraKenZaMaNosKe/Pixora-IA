"""Generates the Pixora Diamond Frame P icon at all required sizes.

Outputs:
  • android/app/src/main/res/drawable-{m,h,x,xx,xxx}hdpi/ic_launcher_foreground.png
  • docs/design/app_icon/play_store_icon_512.png       (Play Store)
  • docs/design/app_icon/preview_512.png               (quick look)

Design:
  - Transparent background (Android tints it via <background>)
  - Outer gold diamond (thin border)
  - Inner gold diamond (thinner, dimmer)
  - P letter in serif italic (Times New Roman Italic — Cormorant would be
    identical in shape for a single glyph), bright gold fill
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent  # repo root
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
DOCS = ROOT / 'docs' / 'design' / 'app_icon'

# Palette
GOLD = (201, 166, 80, 255)
GOLD_DEEP = (138, 111, 51, 210)
GOLD_BRIGHT = (240, 221, 158, 255)

FONT_PATH = 'C:/Windows/Fonts/timesi.ttf'  # Times New Roman Italic — serif italic


def make_icon(size_px: int, out: Path):
    """Render the icon at *size_px* square, write to *out*.

    The coordinate system is the adaptive-icon 108dp viewport, scaled to
    ``size_px``. Content stays within the safe zone (center 66/108 of the
    viewport) so Pixel launchers can mask-crop it without clipping the
    diamonds.
    """
    img = Image.new('RGBA', (size_px, size_px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    scale = size_px / 108.0
    cx = cy = size_px / 2.0

    # Outer diamond — top, right, bottom, left (within safe zone).
    outer_w = 2 * scale
    outer = [
        (cx, 21 * scale),
        (87 * scale, cy),
        (cx, 87 * scale),
        (21 * scale, cy),
    ]
    for i in range(4):
        a, b = outer[i], outer[(i + 1) % 4]
        draw.line([a, b], fill=GOLD, width=max(1, int(outer_w)))

    # Inner diamond — dimmer, thinner.
    inner = [
        (cx, 30 * scale),
        (78 * scale, cy),
        (cx, 78 * scale),
        (30 * scale, cy),
    ]
    inner_w = 1.2 * scale
    for i in range(4):
        a, b = inner[i], inner[(i + 1) % 4]
        draw.line([a, b], fill=GOLD_DEEP, width=max(1, int(inner_w)))

    # P letter — serif italic, centered, bright gold.
    font_size = int(50 * scale)
    font = ImageFont.truetype(FONT_PATH, font_size)
    bbox = draw.textbbox((0, 0), 'P', font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    # Center with small optical offset — italic P leans right, pull left a hair.
    tx = cx - tw / 2 - bbox[0] - 2 * scale
    ty = cy - th / 2 - bbox[1] - 3 * scale
    draw.text((tx, ty), 'P', font=font, fill=GOLD_BRIGHT)

    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, 'PNG', optimize=True)
    print(f'  wrote {size_px}x{size_px} -> {out.relative_to(ROOT)}')


# Android adaptive-icon foreground densities.
densities = {
    'mdpi': 108,       # 1x
    'hdpi': 162,       # 1.5x
    'xhdpi': 216,      # 2x
    'xxhdpi': 324,     # 3x
    'xxxhdpi': 432,    # 4x
}

print('[pixora] generating Android foreground PNGs ...')
for d, size in densities.items():
    out = RES / f'drawable-{d}' / 'ic_launcher_foreground.png'
    make_icon(size, out)

print('\n[pixora] generating Play Store icon 512x512 ...')
make_icon(512, DOCS / 'play_store_icon_512.png')

print('\n[pixora] generating preview 256 ...')
make_icon(256, DOCS / 'preview_256.png')

print('\n✅ all icons generated')
