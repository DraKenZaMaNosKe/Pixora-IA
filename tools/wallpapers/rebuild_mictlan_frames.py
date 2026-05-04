"""
Rebuild Mictlantecuhtli explore frames with the character at a smaller scale
(more depth, less overwhelming) and anchored to the floor.

Source: 61-frame GIF (already has green-screen alpha) + panoramic background.
Output: 61 portrait JPGs (540x960) for the Pixora explore-mode renderer.
"""
from __future__ import annotations
import os, math, random
from pathlib import Path
from PIL import Image, ImageFilter, ImageDraw

SRC_DIR = Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/mitologia/mesoamericana")
GIF_PATH = SRC_DIR / " MICTLANTECUHTLI_gif.gif"
BG_PATH = SRC_DIR / "imagen_fondo_ MICTLANTECUHTLI.png"

OUT_DIR = Path(r"C:/Users/lalo/AppData/Local/Temp/mictlan_frames")
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Target character height as fraction of background height (1080 px)
CHAR_SCALE = 0.30  # 324 px tall — very small, clear depth (v1=0.85, v2=0.55, v3=0.42, v4=0.30)
# Output crop is 9:16 centered on background; downscaled to match other catalog frames
CROP_RATIO = 9 / 16
OUT_WIDTH = 540
OUT_HEIGHT = 960
JPG_QUALITY = 85


def clean_green_halo(rgba: Image.Image) -> Image.Image:
    """Kill leftover green chroma in semi-transparent edge pixels.

    The GIF's palette gives binary alpha (0 or 255) and the green halo around
    the silhouette stays visible after compositing. This zeroes alpha on any
    near-green pixel and fades the alpha on weakly-green ones so the edges
    blend into the background instead of glowing radioactive.
    """
    px = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            # Strong green: kill it
            if g > 180 and r < 110 and b < 110:
                px[x, y] = (0, 0, 0, 0)
            # Weak green tint: reduce alpha + neutralise color
            elif g > r + 25 and g > b + 25:
                # Cap green at the average of red+blue to remove the cast
                neutral = (r + b) // 2
                fade = max(0, 255 - (g - neutral) * 3)
                px[x, y] = (r, neutral, b, min(a, fade))
    return rgba


def main():
    bg = Image.open(BG_PATH).convert("RGBA")
    bg_w, bg_h = bg.size  # 2700 x 1080
    print(f"Background: {bg_w}x{bg_h}")

    gif = Image.open(GIF_PATH)
    n = gif.n_frames
    print(f"GIF: {gif.size}, {n} frames")

    # Use frame 0 to lock the bounding box (so per-frame jitter doesn't
    # cause the character to grow/shrink between frames)
    gif.seek(0)
    f0 = gif.convert("RGBA")
    bbox = f0.getbbox()
    print(f"Frame 0 visible bbox: {bbox} ->{bbox[2]-bbox[0]} x {bbox[3]-bbox[1]}")

    target_h = int(bg_h * CHAR_SCALE)
    src_w, src_h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    target_w = int(src_w * (target_h / src_h))
    print(f"Character target size: {target_w}x{target_h} (scale={CHAR_SCALE})")

    # Position: horizontally centered on bg, anchored to bottom (feet on floor)
    pos_x = bg_w // 2 - target_w // 2
    pos_y = bg_h - target_h
    print(f"Character position on bg: ({pos_x}, {pos_y})")

    # Crop window for the portrait view (centered on background)
    crop_w = int(bg_h * CROP_RATIO)  # ~608
    crop_x = bg_w // 2 - crop_w // 2
    crop_box = (crop_x, 0, crop_x + crop_w, bg_h)
    print(f"Crop window: {crop_box} ->{crop_w}x{bg_h}")

    for i in range(n):
        gif.seek(i)
        char = gif.convert("RGBA").crop(bbox)
        # Clean green halo BEFORE upscaling so artifacts don't get smeared
        char = clean_green_halo(char)
        char = char.resize((target_w, target_h), Image.LANCZOS)

        composed = bg.copy()
        composed.alpha_composite(char, (pos_x, pos_y))
        portrait = composed.crop(crop_box)
        out = portrait.resize((OUT_WIDTH, OUT_HEIGHT), Image.LANCZOS).convert("RGB")
        out.save(OUT_DIR / f"frame_{i+1:04d}.jpg", "JPEG", quality=JPG_QUALITY, optimize=True)

        if (i + 1) % 10 == 0 or i + 1 == n:
            print(f"  rebuilt {i+1}/{n}")

    total = sum(f.stat().st_size for f in OUT_DIR.glob("frame_*.jpg"))
    print(f"\nDone. Total: {total/1024:.0f} KB across {n} frames.")


if __name__ == "__main__":
    main()
