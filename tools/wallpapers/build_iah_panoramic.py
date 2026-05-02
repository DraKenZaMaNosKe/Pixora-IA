"""
Iah Egyptian — Panoramic static wallpaper.

Pre-composites all 8 parallax layers into ONE wide image (4192x2340)
that Samsung's ImageWallpaper treats natively as panoramic — full
compositor-level scroll when the user swipes between home pages,
just like the Akuma panoramic.

Layout:
  · Width 4192 = ~3.9x screen width (1080)
  · Cosmic background (constellations) tiled/scaled across full width
  · Altar group (halo, moon, frame, zodiac wheel, text) composited
    at horizontal CENTER (visible when user is on middle home page)
  · Edges: pure cosmos (visible when user swipes to leftmost/rightmost page)
"""
from PIL import Image
from pathlib import Path

ASSETS = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian")
LAYERS = ASSETS / "parallax_v6"
OUT = ASSETS / "panoramic"
OUT.mkdir(parents=True, exist_ok=True)

# Final dimensions — wide enough that Samsung treats as panoramic
W, H = 4192, 2340           # ~3.9x screen width
SCREEN_W = 1080             # device screen width (used to center altar)


def fit_height(img: Image.Image, target_h: int) -> Image.Image:
    """Scale by height; width follows aspect ratio (no crop)."""
    iw, ih = img.size
    new_w = int(iw * (target_h / ih))
    return img.resize((new_w, target_h), Image.LANCZOS)


# ── 1. Wide cosmic background ──────────────────────────────────────────────
# Use constelaciones (already cosmic with stars). Scale to height H.
print("Cosmic background:")
sky_src = Image.open(ASSETS / "fondo_con_constelaciones.webp").convert("RGBA")
print(f"  source: {sky_src.size}")
sky = fit_height(sky_src, H)
print(f"  scaled to H={H}: {sky.size}")

# If sky is narrower than W, tile horizontally with mirror reflection
canvas = Image.new("RGBA", (W, H), (5, 7, 30, 255))
sky_w = sky.size[0]
if sky_w >= W:
    # Crop center
    x = (sky_w - W) // 2
    canvas.paste(sky.crop((x, 0, x + W, H)), (0, 0))
    print(f"  cropped center: {W}x{H}")
else:
    # Tile with mirroring for seamless edges
    sky_mirror = sky.transpose(Image.FLIP_LEFT_RIGHT)
    x = (W - sky_w) // 2  # center the original
    # Left edge: mirror
    canvas.paste(sky_mirror.crop((sky_w - x, 0, sky_w, H)), (0, 0))
    # Center: original
    canvas.paste(sky, (x, 0))
    # Right edge: mirror
    canvas.paste(sky_mirror.crop((0, 0, W - x - sky_w, H)), (x + sky_w, 0))
    print(f"  tiled (orig at x={x}, mirrors on both sides)")


# ── 2. Composite altar layers at horizontal CENTER ─────────────────────────
# Each parallax layer was built for 1080x2340 viewport. We composite them
# centered horizontally in the panorama so altar/zodiac/text appear when
# user is on the middle home page.
print("\nAltar group (centered):")
center_x = (W - SCREEN_W) // 2  # left edge of screen-sized slot at center

altar_layers = [
    "layer_1_halo.webp",
    "layer_2_moon.webp",
    "layer_3_frame.webp",
    "layer_4_zodiac_far.webp",
    "layer_5_zodiac_mid.webp",
    "layer_6_zodiac_near.webp",
    "layer_7_text.webp",
]

for fn in altar_layers:
    p = LAYERS / fn
    if not p.exists():
        print(f"  [skip] {fn} missing")
        continue
    layer = Image.open(p).convert("RGBA")
    lw, lh = layer.size
    # Pad/scale to 1080x2340 if needed (most should already be that size)
    if (lw, lh) != (SCREEN_W, H):
        layer = fit_height(layer, H)
        lw, lh = layer.size
    # Paste at center
    canvas.alpha_composite(layer, (center_x, 0))
    print(f"  {fn}: {lw}x{lh} pasted at x={center_x}")


# ── 3. Save final panoramic ────────────────────────────────────────────────
out_path = OUT / "iah_egyptian_giza_panoramic.webp"
canvas.convert("RGB").save(out_path, "WEBP", quality=88, method=6)
print(f"\n✅ saved: {out_path}")
print(f"   size: {out_path.stat().st_size:,} bytes ({out_path.stat().st_size/1024:.1f} KB)")
print(f"   dims: {W}x{H}")

# Also save preview thumbnail (540x294 = scaled down 4x for catalog preview)
thumb = canvas.convert("RGB").resize((W // 4, H // 4), Image.LANCZOS)
thumb_path = OUT / "iah_egyptian_giza_panoramic_preview.webp"
thumb.save(thumb_path, "WEBP", quality=72)
print(f"   preview: {thumb_path.stat().st_size:,} bytes")
