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

# Final dimensions — Pixora's panoramic standard from CLAUDE.md.
# Critical: image must be LANDSCAPE (wider than tall) so Samsung's
# ImageWallpaper scales it to fit screen HEIGHT, leaving lots of
# horizontal extra width for the launcher to pan across home pages.
# A square or portrait image at screen height gets cropped, not scrolled.
W, H = 4192, 1024           # ~4.09:1 ratio — matches Akuma-style panoramics
SCREEN_W = 1080             # phone screen width (used to center altar)


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


# ── 2. Composite altar / zodiac / text BAKED IN at horizontal center ─────
# Samsung scales the 4192x1024 source up to fit the 2340-tall screen
# (~×2.28), so the final on-screen image is ~9560 wide. We bake the
# altar group into the source center slice so when the user is on the
# middle home page, they see the altar; swipe left/right reveals more
# cosmos. Scale altar down to 1024 height (the source height) so it
# matches the surrounding bg's vertical resolution.
print("\nAltar group (baked at horizontal center, scaled to H=1024):")
center_x = W // 2  # source center

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
    # Source layers are 1080x2340 (portrait); scale by HEIGHT to match
    # the panoramic source height (1024px). Width follows aspect.
    scaled = fit_height(layer, H)
    sw, sh = scaled.size
    paste_x = center_x - sw // 2
    canvas.alpha_composite(scaled, (paste_x, 0))
    print(f"  {fn}: scaled to {sw}x{sh} pasted at x={paste_x}")


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
