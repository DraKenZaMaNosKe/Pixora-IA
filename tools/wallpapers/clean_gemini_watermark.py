"""Remove Gemini watermark using clone stamp technique.

v3 (2026-07-04): instead of algorithmic inpaint (which averages colors and
blurs texture), we CLONE a patch from the same image shifted horizontally
by ~250 px. This preserves texture, grain and structure fully, so the
result is invisible even in complex scenes (grass, pixel art, foliage).

For safety in mostly-uniform areas (skies, smoke), inpaint is still used
as a fallback when clone would land in an obvious edge or bright zone.

Only processes 4128x1024 PNGs (Gemini ultra-wide). Grok's 1792x1008 JPGs
are skipped (no visible watermark).
"""
import sys
import shutil
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

DEFAULT_SRC = Path(r"C:/Users/lalo/Downloads")
BACKUP_DIRNAME = ".watermark_originals__with_watermark"

# Where to search for the sparkle in a 4128x1024 image
SEARCH = {"x_from_right": 210, "y_from_bottom": 170}

# Sparkle detection
# Note: Gemini adapts watermark BRIGHTNESS to the background. On bright
# scenes (grass, sky) the sparkle is white 240+. On dark scenes (castles
# at night, netherworlds) it dims to ~120-140 gray. Detection is tricky.
# Strategy: try HIGH threshold first for obvious cases; if fails, use a
# generous FALLBACK_BOX that covers the whole typical watermark zone.
BRIGHT_THRESHOLD = 195
MIN_SPARKLE_PIXELS = 15
MASK_DILATE_PX = 8
EXTRA_PAD = 25
FEATHER_PX = 12  # bigger feather = smoother edge blend = less visible patch

# Clone source shift — how far to the LEFT we borrow pixels from.
# 260 px puts us safely outside any possible watermark tail.
CLONE_SHIFT_X = 240  # far enough from a 180px watermark box

# Fallback box (used when sparkle is too dim to detect). Generous
# enough to cover the watermark on any position variant Gemini uses.
# Because clone stamp preserves texture, over-covering is safe.
FALLBACK_BOX = {
    "x_from_right": 200,
    "x_pad_right": 20,
    "y_from_bottom": 160,
    "y_pad_bottom": 20,
}  # 180x140 — generous coverage; hybrid approach makes size safe

# Threshold to decide between inpaint (gradient scenes) vs clone stamp
# (textured scenes). Measured as std deviation of luminance in the box
# neighborhood. Low std = uniform gradient → inpaint. High std = texture
# → clone.
TEXTURE_STD_THRESHOLD = 22.0


def detect_sparkle_box(img_bgr: np.ndarray) -> tuple[int, int, int, int, str]:
    """Return (x0, y0, x1, y1, method). Bounding box of the sparkle
    with padding, plus 'detected' or 'fallback'."""
    h, w = img_bgr.shape[:2]
    sx0 = w - SEARCH["x_from_right"]
    sy0 = h - SEARCH["y_from_bottom"]
    region = img_bgr[sy0:h, sx0:w]

    gray = cv2.cvtColor(region, cv2.COLOR_BGR2GRAY)
    _, bright = cv2.threshold(gray, BRIGHT_THRESHOLD, 255, cv2.THRESH_BINARY)
    if int(bright.sum() / 255) < MIN_SPARKLE_PIXELS:
        fb = FALLBACK_BOX
        return (
            w - fb["x_from_right"], h - fb["y_from_bottom"],
            w - fb["x_pad_right"], h - fb["y_pad_bottom"],
            "fallback",
        )

    ys, xs = np.where(bright > 0)
    raw_w = int(xs.max()) - int(xs.min())
    raw_h = int(ys.max()) - int(ys.min())
    # Sanity: sparkle real es ~50x50. Si detected > 120 en algún lado,
    # significa que había blancos NO watermark (flores, nubes, etc).
    # En ese caso, usar box fallback fijo (esquina inferior derecha).
    if raw_w > 120 or raw_h > 120:
        fb = FALLBACK_BOX
        return (
            w - fb["x_from_right"], h - fb["y_from_bottom"],
            w - fb["x_pad_right"], h - fb["y_pad_bottom"],
            "fallback_too_bright",
        )
    pad = MASK_DILATE_PX + EXTRA_PAD
    x0 = sx0 + int(xs.min()) - pad
    x1 = sx0 + int(xs.max()) + pad
    y0 = sy0 + int(ys.min()) - pad
    y1 = sy0 + int(ys.max()) + pad
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(w, x1), min(h, y1)
    return x0, y0, x1, y1, "detected"


def clone_patch(img_bgr: np.ndarray, x0: int, y0: int, x1: int, y1: int,
                shift_x: int = CLONE_SHIFT_X) -> np.ndarray:
    """Copy a patch from (x0-shift_x, y0) into (x0, y0) with feather blend.

    Returns modified image (copy)."""
    h, w = img_bgr.shape[:2]
    out = img_bgr.copy()
    pw = x1 - x0
    ph = y1 - y0

    # Source coordinates (shifted left by shift_x)
    src_x0 = max(0, x0 - shift_x)
    src_x1 = src_x0 + pw
    if src_x1 > x0:  # would overlap with target — impossible if shift large enough
        src_x1 = x0
        src_x0 = src_x1 - pw
    src_y0, src_y1 = y0, y1

    src_patch = out[src_y0:src_y1, src_x0:src_x1].astype(np.float32)
    tgt_patch = out[y0:y1, x0:x1].astype(np.float32)

    # Feather mask: 1 in the center, gradient to 0 at edges over FEATHER_PX
    fmask = np.ones((ph, pw), dtype=np.float32)
    for i in range(FEATHER_PX):
        v = i / FEATHER_PX
        if i < ph:
            fmask[i, :] = np.minimum(fmask[i, :], v)
            fmask[ph - 1 - i, :] = np.minimum(fmask[ph - 1 - i, :], v)
        if i < pw:
            fmask[:, i] = np.minimum(fmask[:, i], v)
            fmask[:, pw - 1 - i] = np.minimum(fmask[:, pw - 1 - i], v)
    fmask_3ch = np.stack([fmask] * 3, axis=-1)

    blended = src_patch * fmask_3ch + tgt_patch * (1.0 - fmask_3ch)
    out[y0:y1, x0:x1] = blended.astype(np.uint8)
    return out


def clean_watermark(src_path: Path, backup_path: Path) -> str:
    if not backup_path.exists():
        shutil.copy2(src_path, backup_path)

    img = cv2.imread(str(src_path), cv2.IMREAD_COLOR)
    if img is None:
        return "error"
    h, w = img.shape[:2]

    is_gemini = (w == 4128 and h == 1024)
    if not is_gemini:
        return "skipped_size"

    x0, y0, x1, y1, method = detect_sparkle_box(img)

    # Analyze neighborhood texture (area ABOVE the watermark box) to
    # decide inpaint (for gradients) vs clone (for textures). This avoids
    # visible patches on smoke/sky and preserves detail on grass/rocks.
    neighbor_h = min(60, y0)
    if neighbor_h > 10:
        neighbor = img[y0 - neighbor_h: y0, x0: x1]
        gray_n = cv2.cvtColor(neighbor, cv2.COLOR_BGR2GRAY)
        tex_std = float(gray_n.std())
    else:
        tex_std = 100.0  # default to clone if we can't measure

    if tex_std < TEXTURE_STD_THRESHOLD:
        # Gradient scene → inpaint blends naturally
        mask = np.zeros(img.shape[:2], dtype=np.uint8)
        mask[y0:y1, x0:x1] = 255
        cleaned = cv2.inpaint(img, mask, 7, cv2.INPAINT_TELEA)
        method += "_inpaint"
    else:
        # Textured scene → clone stamp preserves detail
        cleaned = clone_patch(img, x0, y0, x1, y1)
        method += "_clone"

    cleaned_rgb = cv2.cvtColor(cleaned, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(cleaned_rgb)
    if src_path.suffix.lower() == ".png":
        pil_img.save(src_path, "PNG", optimize=True)
    else:
        pil_img.save(src_path, "JPEG", quality=92, optimize=True)
    return f"cleaned_{method}"


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    if not src.is_dir():
        print(f"ERROR: {src} no es una carpeta valida")
        sys.exit(1)

    backup_dir = src / BACKUP_DIRNAME
    backup_dir.mkdir(exist_ok=True)

    print(f"=== Cleaning Gemini watermarks v3 (clone stamp) in {src} ===")
    print(f"Backups -> {backup_dir}")
    print()

    stats = {}
    for f in sorted(src.iterdir()):
        if not f.is_file():
            continue
        if f.suffix.lower() not in (".png", ".jpg", ".jpeg"):
            continue
        backup_path = backup_dir / f.name
        status = clean_watermark(f, backup_path)
        stats[status] = stats.get(status, 0) + 1
        icon = {
            "cleaned_detected": "OK",
            "cleaned_fallback": "OK~",
            "skipped_size": "--",
            "error": "!!",
        }.get(status, "??")
        print(f"  [{icon:>3s}] {f.name:<40s} ({status})")

    print()
    print(f"=== Summary ===")
    for k, v in sorted(stats.items()):
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
