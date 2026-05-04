"""Filter Gemini PNGs by recent modification time (last 4 hours) and
analyze each one — match to its likely zodiac sign by composition / color."""
from __future__ import annotations
import sys
from pathlib import Path
from datetime import datetime, timedelta

sys.stdout.reconfigure(encoding="utf-8")

from PIL import Image

DOWNLOADS = Path(r"C:/Users/lalo/Downloads")
RECENT_HOURS = 4

# All Gemini files
all_files = list(DOWNLOADS.glob("Gemini_Generated_Image_*.png"))
# Filter to recent
cutoff = datetime.now() - timedelta(hours=RECENT_HOURS)
recent = sorted(
    [f for f in all_files if datetime.fromtimestamp(f.stat().st_mtime) > cutoff],
    key=lambda f: f.stat().st_mtime,
)

print(f"Found {len(all_files)} total Gemini PNGs in Downloads")
print(f"Filtered to {len(recent)} from last {RECENT_HOURS} hours\n")


def classify(img: Image.Image) -> tuple[str, str, str]:
    w, h = img.size
    # Bg from corners
    corners = [img.getpixel((0, 0)), img.getpixel((w-1, 0)),
               img.getpixel((0, h-1)), img.getpixel((w-1, h-1))]
    avg = [sum(c[i] for c in corners) // 4 for i in range(3)]
    if avg[1] > avg[0] + 50 and avg[1] > avg[2] + 50:
        bg = "GREEN"
    elif avg[0] > 150 and avg[2] > 150 and avg[1] < avg[0] - 50:
        bg = "MAGENTA"
    else:
        bg = "OTHER"
    # Sample center 50%
    cx0, cy0 = int(w * 0.25), int(h * 0.25)
    cx1, cy1 = int(w * 0.75), int(h * 0.75)
    crop = img.crop((cx0, cy0, cx1, cy1)).convert("RGB").resize((30, 30))
    # Find dominant non-bg color
    from collections import Counter
    c = Counter()
    for x in range(30):
        for y in range(30):
            r, g, b = crop.getpixel((x, y))
            if bg == "GREEN" and g > r + 60 and g > b + 60: continue
            if bg == "MAGENTA" and r > 150 and b > 150 and g < r - 60: continue
            if r + g + b < 60: continue  # skip near-black
            c[(r // 32 * 32, g // 32 * 32, b // 32 * 32)] += 1
    dom = c.most_common(1)[0][0] if c else (0, 0, 0)
    r, g, b = dom
    # Element guess
    if r > 130 and g < 130 and b < 100:
        elem = "FIRE"
    elif g > r and g > b and g > 80:
        elem = "EARTH"
    elif b > 100 and (b > r or b > g):
        if r > g and abs(r - b) < 80:
            elem = "AIR"
        else:
            elem = "WATER"
    elif r > 100 and b > 100 and g < min(r, b):
        elem = "AIR"
    else:
        elem = f"?({r},{g},{b})"
    return bg, elem, str(dom)


print(f"{'Time':6s} {'File':40s} {'Bg':9s} {'Element':10s} {'Dominant'}")
print("-" * 100)
for fp in recent:
    img = Image.open(fp).convert("RGB")
    bg, elem, dom = classify(img)
    t = datetime.fromtimestamp(fp.stat().st_mtime).strftime("%H:%M")
    print(f"{t:6s} {fp.name[:40]:40s} {bg:9s} {elem:10s} {dom}")
