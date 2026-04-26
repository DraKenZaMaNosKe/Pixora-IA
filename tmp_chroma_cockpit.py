"""Chroma-key the bright green windshield out of a Gemini cockpit PNG.

Steps:
  1. Read source PNG (Gemini output, e.g. 1536x2752)
  2. For every pixel: if green is dominant (G > R*1.3 AND G > B*1.3 AND G > 100),
     set alpha = 0. Smooth edge using "spill suppression" (reduce green channel
     in semi-transparent border to avoid green halo).
  3. Resize to 1080x2340 (Pixora standard portrait wallpaper).
  4. Save as transparent PNG → ready to composite.

Then ALSO:
  5. Composite cockpit on top of carretera_nocturna.webp bg → final WebP.
  6. Save as wallpapers_new/static/pixora_carretera_suv.webp.

Usage:
  python tmp_chroma_cockpit.py <input_png>
  (defaults to ~/Downloads/auto_design.png if no arg)
"""
import sys
import os
from pathlib import Path

import numpy as np
from PIL import Image


def chroma_key_green(im_rgba: Image.Image) -> Image.Image:
    """Returns RGBA image with bright green areas converted to transparent."""
    arr = np.array(im_rgba.convert("RGBA"))
    r = arr[:, :, 0].astype(np.int32)
    g = arr[:, :, 1].astype(np.int32)
    b = arr[:, :, 2].astype(np.int32)
    # Strong green: G dominates R and B by margin AND has reasonable brightness
    is_green = (g > r * 1.25) & (g > b * 1.25) & (g > 100)
    # Soft mask: distance from "very green" → blend the alpha
    # Compute a continuous 0..255 alpha based on green-dominance score
    score = np.maximum(0, np.minimum(g - np.maximum(r, b), 255))
    # Where is_green is True: alpha = 0
    # Where score is high but not is_green: partial alpha (soft edge)
    alpha = arr[:, :, 3].copy()
    alpha[is_green] = 0
    # Spill suppression on semi-transparent edges: reduce green channel
    edge_mask = (~is_green) & (score > 30)
    arr[:, :, 1] = np.where(edge_mask,
        np.minimum(g, (r + b) // 2 + 10).astype(np.uint8),
        arr[:, :, 1])
    arr[:, :, 3] = alpha
    return Image.fromarray(arr, mode="RGBA")


def main():
    src_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        os.path.expanduser("~/Downloads/auto_design.png"))
    if not src_path.is_file():
        # Try newer naming convention
        for cand in ["pixora_suv.png", "auto_design (1).png", "auto_design.png"]:
            p = Path(os.path.expanduser(f"~/Downloads/{cand}"))
            if p.is_file():
                src_path = p
                break
    if not src_path.is_file():
        print(f"FAIL: source PNG not found at {src_path}")
        print("Expected: ~/Downloads/auto_design.png or pass path as arg")
        sys.exit(1)
    print(f"source: {src_path}")
    im = Image.open(src_path)
    print(f"  size: {im.size}, mode: {im.mode}")

    keyed = chroma_key_green(im)
    out_dir = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/drive")
    out_dir.mkdir(parents=True, exist_ok=True)
    keyed_path = out_dir / "cockpit_suv_keyed.png"
    keyed.save(keyed_path, "PNG")
    print(f"  keyed → {keyed_path}  ({keyed_path.stat().st_size/1024:.0f} KB)")

    # Resize cockpit to 1080x2340
    cockpit_1080 = keyed.resize((1080, 2340), Image.Resampling.LANCZOS)

    # Composite cockpit on top of the existing carretera_nocturna bg
    bg_path = Path(r"D:/Orbix/Pixora-IA/wallpapers_new/static/pixora_carretera_nocturna.webp")
    if bg_path.is_file():
        bg = Image.open(bg_path).convert("RGBA").resize((1080, 2340), Image.Resampling.LANCZOS)
        composite = Image.alpha_composite(bg, cockpit_1080)
        out_full = Path(r"D:/Orbix/Pixora-IA/wallpapers_new/static/pixora_carretera_suv.webp")
        out_prev = Path(r"D:/Orbix/Pixora-IA/wallpapers_new/previews/pixora_carretera_suv_preview.webp")
        composite.convert("RGB").save(out_full, "WEBP", quality=88, method=6)
        composite.convert("RGB").resize((540, 1170), Image.Resampling.LANCZOS).save(
            out_prev, "WEBP", quality=82, method=6)
        print(f"  composite full → {out_full}  ({out_full.stat().st_size/1024:.0f} KB)")
        print(f"  composite prev → {out_prev}  ({out_prev.stat().st_size/1024:.0f} KB)")
    else:
        print(f"  WARN: no bg at {bg_path} — composite skipped")


if __name__ == "__main__":
    main()
