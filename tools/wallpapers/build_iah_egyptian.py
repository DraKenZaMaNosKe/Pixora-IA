"""
Compone el wallpaper Iah Egyptian (diseño #02 Hieroglifo) en 1080x2340.
Output: docs/design/concepts/livecalendar/egyptian/pixora_iah_egyptian_giza.webp
        + preview pixora_iah_egyptian_giza_preview.webp
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path

ASSETS = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian")
OUT_FULL = ASSETS / "pixora_iah_egyptian_giza.webp"
OUT_PREV = ASSETS / "pixora_iah_egyptian_giza_preview.webp"

W, H = 1080, 2340  # spec Pixora wallpaper portrait

# ─── Load layers ────────────────────────────────────────────────────────────
bg = Image.open(ASSETS / "bg_sky_lapis.png").convert("RGBA")
landscape = Image.open(ASSETS / "landscape_giza.png").convert("RGBA")
frame = Image.open(ASSETS / "frame_hieroglyph.png").convert("RGBA")
halo = Image.open(ASSETS / "halo_gold.png").convert("RGBA")
moon = Image.open(ASSETS / "moon_d14_full.png").convert("RGBA")  # default = full

# ─── Compose canvas ─────────────────────────────────────────────────────────
canvas = Image.new("RGBA", (W, H), (10, 14, 58, 255))  # lapis fallback fill

# 1. Background sky (cover-fit)
def fit_cover(img: Image.Image, target_w: int, target_h: int) -> Image.Image:
    iw, ih = img.size
    src_ratio = iw / ih
    tgt_ratio = target_w / target_h
    if src_ratio > tgt_ratio:  # img wider → match height, crop sides
        new_h = target_h
        new_w = int(new_h * src_ratio)
    else:
        new_w = target_w
        new_h = int(new_w / src_ratio)
    img = img.resize((new_w, new_h), Image.LANCZOS)
    left = (new_w - target_w) // 2
    top = (new_h - target_h) // 2
    return img.crop((left, top, left + target_w, top + target_h))

bg_fit = fit_cover(bg, W, H)
canvas.paste(bg_fit, (0, 0), bg_fit)

# 2. Add subtle starfield (programmatic — no asset needed)
import random
random.seed(528)  # reproducible
star_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sd = ImageDraw.Draw(star_layer)
for _ in range(180):
    x = random.randint(0, W)
    y = random.randint(0, int(H * 0.65))  # only above landscape
    radius = random.choice([1, 1, 1, 2, 2, 3])
    alpha = random.randint(120, 240)
    color = random.choice([
        (255, 255, 255, alpha),
        (245, 214, 118, alpha),  # gold
        (200, 220, 255, alpha),  # cool white
    ])
    sd.ellipse([x-radius, y-radius, x+radius, y+radius], fill=color)
canvas = Image.alpha_composite(canvas, star_layer)

# 3. Halo behind moon (top-center area, big)
halo_size = 900
halo_resized = halo.resize((halo_size, halo_size), Image.LANCZOS)
halo_x = (W - halo_size) // 2
halo_y = 380
# add slight glow around halo
halo_glow = halo_resized.filter(ImageFilter.GaussianBlur(radius=20))
canvas.alpha_composite(halo_glow, (halo_x, halo_y))
canvas.alpha_composite(halo_resized, (halo_x, halo_y))

# 4. Moon centered inside halo
moon_size = 600
moon_resized = moon.resize((moon_size, moon_size), Image.LANCZOS)
moon_x = (W - moon_size) // 2
moon_y = halo_y + (halo_size - moon_size) // 2
canvas.alpha_composite(moon_resized, (moon_x, moon_y))

# 5. Frame hieroglifo OVER the moon (frames it)
frame_size = 1000
frame_resized = frame.resize((frame_size, frame_size), Image.LANCZOS)
frame_x = (W - frame_size) // 2
frame_y = halo_y + (halo_size - frame_size) // 2
canvas.alpha_composite(frame_resized, (frame_x, frame_y))

# 6. Landscape silhouette at the bottom
land_h = int(H * 0.32)
land_w = W
landscape_fit = landscape.resize((land_w, land_h), Image.LANCZOS)
canvas.alpha_composite(landscape_fit, (0, H - land_h))

# 7. Soft vignette dark at edges
vignette = Image.new("RGBA", (W, H), (0, 0, 0, 0))
vd = ImageDraw.Draw(vignette)
for i in range(60):
    alpha = int(2 + i * 1.2)
    vd.rectangle([i*5, i*5, W-i*5, H-i*5], outline=(0, 0, 0, alpha), width=1)
canvas = Image.alpha_composite(canvas, vignette)

# 8. Personal data overlay (placeholder — engine will replace at runtime)
# Try to load Cinzel from system; fallback to default
try:
    font_paths_try = [
        r"C:/Windows/Fonts/Cinzel-Bold.ttf",
        r"C:/Windows/Fonts/Cinzel-Regular.ttf",
        r"C:/Windows/Fonts/georgia.ttf",
        r"C:/Windows/Fonts/serif.ttf",
    ]
    font_big = font_med = font_sm = None
    for fp in font_paths_try:
        if Path(fp).exists():
            font_big = ImageFont.truetype(fp, 80)
            font_med = ImageFont.truetype(fp, 36)
            font_sm  = ImageFont.truetype(fp, 24)
            break
    if font_big is None:
        font_big = ImageFont.load_default()
        font_med = ImageFont.load_default()
        font_sm  = ImageFont.load_default()
except Exception as e:
    print(f"font load: {e}")
    font_big = font_med = font_sm = ImageFont.load_default()

text_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
td = ImageDraw.Draw(text_layer)

def text_with_glow(draw, pos, text, font, fill, glow_color, glow_radius=8):
    x, y = pos
    # Draw glow by drawing text multiple times slightly offset
    for dx in range(-glow_radius, glow_radius+1, 2):
        for dy in range(-glow_radius, glow_radius+1, 2):
            if dx*dx + dy*dy <= glow_radius*glow_radius:
                draw.text((x+dx, y+dy), text, font=font, fill=glow_color)
    draw.text(pos, text, font=font, fill=fill)

# Personal block bottom area (above landscape silhouette)
text_y_start = H - int(land_h * 0.85)

# Greeting
greet = "𓂀  Salve  𓂀"
bbox = td.textbbox((0, 0), greet, font=font_sm)
gw = bbox[2] - bbox[0]
td.text(((W - gw) // 2, text_y_start), greet, font=font_sm, fill=(200, 152, 96, 220))

# Name (big, glowing gold)
name = "Eduardo"
bbox = td.textbbox((0, 0), name, font=font_big)
nw = bbox[2] - bbox[0]
text_with_glow(td, ((W - nw) // 2, text_y_start + 60), name, font_big,
               fill=(245, 214, 118, 255),
               glow_color=(212, 175, 55, 35),
               glow_radius=10)

# Phase line
phase = "月  Cuarto Creciente"
bbox = td.textbbox((0, 0), phase, font=font_med)
pw = bbox[2] - bbox[0]
td.text(((W - pw) // 2, text_y_start + 175), phase, font=font_med, fill=(255, 255, 255, 240))

# Info line
info = "TAURO  ·  528 HZ  ·  12 · 06 · 2026"
bbox = td.textbbox((0, 0), info, font=font_sm)
iw = bbox[2] - bbox[0]
td.text(((W - iw) // 2, text_y_start + 235), info, font=font_sm, fill=(212, 175, 55, 230))

canvas = Image.alpha_composite(canvas, text_layer)

# ─── Save ─────────────────────────────────────────────────────────────────
canvas_rgb = canvas.convert("RGB")
canvas_rgb.save(OUT_FULL, "WEBP", quality=88, method=6)
print(f"Saved: {OUT_FULL.name} ({OUT_FULL.stat().st_size:,} bytes)")

# Preview 540x1170 < 50KB
preview = canvas_rgb.resize((540, 1170), Image.LANCZOS)
preview.save(OUT_PREV, "WEBP", quality=72, method=6)
print(f"Saved: {OUT_PREV.name} ({OUT_PREV.stat().st_size:,} bytes)")
