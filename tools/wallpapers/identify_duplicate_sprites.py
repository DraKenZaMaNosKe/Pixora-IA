"""
Analyze the 13 zodiac sprite PNGs the user downloaded from Gemini.
Identifies which one is the duplicate by:
  1. Detecting bg color (green chroma vs magenta chroma)
  2. Extracting dominant non-bg colors → guesses element (fire/earth/air/water)
  3. Computing perceptual hash (pHash) for visual similarity
  4. Reporting which pair is most similar = the duplicate
  5. Suggesting which 12 unique sigils we have + their probable zodiac matches
"""
from __future__ import annotations
import sys
from pathlib import Path
from collections import Counter

sys.stdout.reconfigure(encoding="utf-8")

try:
    from PIL import Image
except ImportError:
    print("Install PIL: pip install Pillow")
    sys.exit(1)

DOWNLOADS = Path(r"C:/Users/lalo/Downloads")

# Match Gemini default download names (Gemini_Generated_Image_*.png)
sprite_files = sorted(DOWNLOADS.glob("Gemini_Generated_Image_*.png"))
print(f"Found {len(sprite_files)} Gemini PNG files in Downloads\n")

if not sprite_files:
    print("No Gemini files found. Check the path / filenames.")
    sys.exit(0)


def classify_bg(img: Image.Image) -> str:
    """Sample 4 corner pixels — if avg green > red & blue → green chroma.
    If red & blue ~equal and high → magenta chroma."""
    w, h = img.size
    corners = [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]
    avg_r = avg_g = avg_b = 0
    for x, y in corners:
        r, g, b = img.getpixel((x, y))[:3]
        avg_r += r
        avg_g += g
        avg_b += b
    avg_r //= 4; avg_g //= 4; avg_b //= 4
    if avg_g > avg_r + 50 and avg_g > avg_b + 50:
        return "GREEN"
    if avg_r > 150 and avg_b > 150 and avg_g < avg_r - 50:
        return "MAGENTA"
    return f"OTHER (R{avg_r} G{avg_g} B{avg_b})"


def dominant_subject_color(img: Image.Image, bg_color: str) -> tuple[int, int, int]:
    """Get the dominant color in the center 60% of the image, ignoring
    pixels close to the bg chroma color."""
    w, h = img.size
    cx0, cy0 = int(w * 0.2), int(h * 0.2)
    cx1, cy1 = int(w * 0.8), int(h * 0.8)
    crop = img.crop((cx0, cy0, cx1, cy1)).convert("RGB")
    # Resize for speed
    crop = crop.resize((50, 50))
    counts = Counter()
    for x in range(50):
        for y in range(50):
            r, g, b = crop.getpixel((x, y))
            # Skip near-chroma bg pixels
            if bg_color == "GREEN" and g > r + 60 and g > b + 60:
                continue
            if bg_color == "MAGENTA" and r > 150 and b > 150 and g < r - 60:
                continue
            # Quantize to 32-step buckets
            bucket = (r // 32 * 32, g // 32 * 32, b // 32 * 32)
            counts[bucket] += 1
    if not counts:
        return (0, 0, 0)
    return counts.most_common(1)[0][0]


def color_to_element(rgb: tuple[int, int, int]) -> str:
    r, g, b = rgb
    # FIRE: warm reds/oranges (high R, low B)
    if r > 150 and g < 150 and b < 100:
        return "FIRE"
    # EARTH: greens (G dominant, but the bg might also be greenish — careful)
    if g > 100 and g > r and g > b:
        return "EARTH"
    # WATER: blues/teals (B + G high, low R)
    if b > 120 and g > 100 and r < 150:
        return "WATER"
    # AIR: lilacs/purples (R + B similar, G lower)
    if r > 100 and b > 100 and abs(r - b) < 60 and g < r:
        return "AIR"
    return f"UNKNOWN ({r},{g},{b})"


def phash(img: Image.Image, size: int = 16) -> int:
    """Simple perceptual hash for similarity comparison."""
    small = img.convert("L").resize((size, size), Image.LANCZOS)
    pixels = list(small.getdata())
    avg = sum(pixels) / len(pixels)
    bits = "".join("1" if p >= avg else "0" for p in pixels)
    return int(bits, 2)


def hamming(a: int, b: int) -> int:
    return bin(a ^ b).count("1")


print("Analyzing each sprite...\n")
results = []
for fp in sprite_files:
    img = Image.open(fp).convert("RGB")
    bg = classify_bg(img)
    dom = dominant_subject_color(img, bg)
    elem = color_to_element(dom)
    h = phash(img)
    results.append({"file": fp.name, "bg": bg, "dom": dom, "elem": elem, "phash": h})
    print(f"  {fp.name[-30:]:30s}  bg={bg:8s}  dom={str(dom):16s}  elem={elem}")

# Find the most similar pair (lowest hamming distance) → likely duplicate
print("\nSearching for duplicate (most visually similar pair)...\n")
best_pair = None
best_dist = 1e9
for i in range(len(results)):
    for j in range(i + 1, len(results)):
        d = hamming(results[i]["phash"], results[j]["phash"])
        if d < best_dist:
            best_dist = d
            best_pair = (i, j)

if best_pair:
    i, j = best_pair
    print(f"MOST SIMILAR PAIR (hamming distance {best_dist}/256 — lower = more similar):")
    print(f"  A: {results[i]['file']}")
    print(f"     bg={results[i]['bg']} elem={results[i]['elem']}")
    print(f"  B: {results[j]['file']}")
    print(f"     bg={results[j]['bg']} elem={results[j]['elem']}")
    print()
    print(f"→ One of these is likely the duplicate. Check both visually.")

# Element histogram to see what we have
print("\nElement histogram (we expect 3 of each: 3 fire, 3 earth, 3 air, 3 water = 12):")
elems = Counter(r["elem"] for r in results)
for e, c in elems.most_common():
    marker = " ← OVER" if c > 3 and e != "UNKNOWN" else ""
    print(f"  {e:10s} x{c}{marker}")
