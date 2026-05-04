"""
Genera capas SEPARADAS para parallax 3D del Iah Egyptian.
Cada capa se renderea con su propio parallax_factor y z-order, dándole
profundidad al gyro.

Output (en docs/design/concepts/livecalendar/egyptian/parallax/):
  layer_0_sky.webp           — fondo lapis con estrellas (z=0, factor 0.10)
  layer_1_halo.webp          — halo dorado (z=1, factor 0.35)
  layer_2_moon.webp          — luna (z=2, factor 0.55)
  layer_3_frame.webp         — frame jeroglifico (z=3, factor 0.70)
  layer_4_landscape.webp     — pirámides + arena (z=4, factor 1.00)
  layer_5_text.webp          — texto Eduardo + datos (z=5, factor 1.20, MVP — v1.7 lo renderiza Flutter)
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import random

ASSETS = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian")
OUT = ASSETS / "parallax"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1080, 2340

# ─── Carga assets fuente ──────────────────────────────────────────────────
bg = Image.open(ASSETS / "bg_sky_lapis.png").convert("RGBA")
landscape = Image.open(ASSETS / "landscape_giza.png").convert("RGBA")
frame = Image.open(ASSETS / "frame_hieroglyph.png").convert("RGBA")
halo = Image.open(ASSETS / "halo_gold.png").convert("RGBA")
moon = Image.open(ASSETS / "moon_d14_full.png").convert("RGBA")


def fit_cover(img, target_w, target_h):
    iw, ih = img.size
    src_ratio = iw / ih
    tgt_ratio = target_w / target_h
    if src_ratio > tgt_ratio:
        new_h, new_w = target_h, int(target_h * src_ratio)
    else:
        new_w, new_h = target_w, int(target_w / src_ratio)
    img = img.resize((new_w, new_h), Image.LANCZOS)
    left, top = (new_w - target_w) // 2, (new_h - target_h) // 2
    return img.crop((left, top, left + target_w, top + target_h))


def save_webp(img, name, quality=85):
    p = OUT / name
    img.save(p, "WEBP", quality=quality, method=6)
    print(f"  {name:30s} {p.stat().st_size:>10,} b")


# ═══ LAYER 0 — Cielo lapis con estrellas (más profundo) ══════════════════════
print("\nBuilding layer_0_sky.webp ...")
# Layer needs to be SLIGHTLY larger than the screen to allow gyro pan without
# revealing the edges. Add 8% margin.
LM = int(W * 0.08)
W0, H0 = W + 2*LM, H + 2*LM
sky = fit_cover(bg, W0, H0)
# Add starfield onto the sky directly (so they're part of the background plate)
random.seed(528)
sd = ImageDraw.Draw(sky)
for _ in range(220):
    x = random.randint(0, W0)
    y = random.randint(0, int(H0 * 0.7))
    radius = random.choice([1, 1, 1, 1, 2, 2, 3])
    alpha = random.randint(140, 250)
    color = random.choice([
        (255, 255, 255, alpha),
        (245, 214, 118, alpha),
        (200, 220, 255, alpha),
    ])
    sd.ellipse([x-radius, y-radius, x+radius, y+radius], fill=color)
save_webp(sky.convert("RGB"), "layer_0_sky.webp", quality=82)


# ═══ LAYER 1 — Halo dorado (z=1, mid-deep) ═══════════════════════════════════
print("\nBuilding layer_1_halo.webp ...")
halo_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
halo_size = 920
halo_resized = halo.resize((halo_size, halo_size), Image.LANCZOS)
# Add subtle outer glow
glow = halo_resized.filter(ImageFilter.GaussianBlur(radius=18))
halo_x, halo_y = (W - halo_size) // 2, 380
halo_layer.alpha_composite(glow, (halo_x, halo_y))
halo_layer.alpha_composite(halo_resized, (halo_x, halo_y))
save_webp(halo_layer, "layer_1_halo.webp", quality=88)


# ═══ LAYER 2 — Luna (z=2, foco) ══════════════════════════════════════════════
print("\nBuilding layer_2_moon.webp ...")
moon_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
moon_size = 600
moon_resized = moon.resize((moon_size, moon_size), Image.LANCZOS)
moon_x = (W - moon_size) // 2
moon_y = 380 + (920 - moon_size) // 2  # centered inside halo
moon_layer.alpha_composite(moon_resized, (moon_x, moon_y))
save_webp(moon_layer, "layer_2_moon.webp", quality=88)


# ═══ LAYER 3 — Frame jeroglifico (z=3, sobre la luna) ════════════════════════
print("\nBuilding layer_3_frame.webp ...")
frame_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
frame_size = 1010
frame_resized = frame.resize((frame_size, frame_size), Image.LANCZOS)
frame_x = (W - frame_size) // 2
frame_y = 380 + (920 - frame_size) // 2
frame_layer.alpha_composite(frame_resized, (frame_x, frame_y))
save_webp(frame_layer, "layer_3_frame.webp", quality=88)


# ═══ LAYER 4 — Pirámides + arena (z=4, foreground) ══════════════════════════
print("\nBuilding layer_4_landscape.webp ...")
land_h = int(H * 0.34)
land_w = W
landscape_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
landscape_fit = landscape.resize((land_w, land_h), Image.LANCZOS)
landscape_layer.alpha_composite(landscape_fit, (0, H - land_h))
save_webp(landscape_layer, "layer_4_landscape.webp", quality=88)


# ═══ LAYER 5 — Texto personal (z=5, MVP) ═════════════════════════════════════
# IMPORTANTE: en v1.7 esto será renderizado por Flutter en runtime con datos
# reales de Hive. Para MVP horneo "Eduardo" como demo.
print("\nBuilding layer_5_text.webp ...")
text_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
td = ImageDraw.Draw(text_layer)
try:
    fp = r"C:/Windows/Fonts/georgia.ttf"
    font_big = ImageFont.truetype(fp, 90)
    font_med = ImageFont.truetype(fp, 38)
    font_sm  = ImageFont.truetype(fp, 24)
except Exception:
    font_big = font_med = font_sm = ImageFont.load_default()


def text_with_glow(draw, pos, text, font, fill, glow_color, glow_radius=8):
    x, y = pos
    for dx in range(-glow_radius, glow_radius+1, 2):
        for dy in range(-glow_radius, glow_radius+1, 2):
            if dx*dx + dy*dy <= glow_radius*glow_radius:
                draw.text((x+dx, y+dy), text, font=font, fill=glow_color)
    draw.text(pos, text, font=font, fill=fill)


text_y_start = H - int(land_h * 0.85)
greet = "—  Salve  —"
bbox = td.textbbox((0, 0), greet, font=font_sm)
gw = bbox[2] - bbox[0]
td.text(((W - gw) // 2, text_y_start), greet, font=font_sm, fill=(200, 152, 96, 220))

name = "Eduardo"
bbox = td.textbbox((0, 0), name, font=font_big)
nw = bbox[2] - bbox[0]
text_with_glow(td, ((W - nw) // 2, text_y_start + 50), name, font_big,
               fill=(245, 214, 118, 255),
               glow_color=(212, 175, 55, 35), glow_radius=10)

phase = "Cuarto Creciente"
bbox = td.textbbox((0, 0), phase, font=font_med)
pw = bbox[2] - bbox[0]
td.text(((W - pw) // 2, text_y_start + 175), phase, font=font_med, fill=(255, 255, 255, 240))

info = "TAURO  ·  528 HZ  ·  12 · 06 · 2026"
bbox = td.textbbox((0, 0), info, font=font_sm)
iw_ = bbox[2] - bbox[0]
td.text(((W - iw_) // 2, text_y_start + 240), info, font=font_sm, fill=(212, 175, 55, 230))

save_webp(text_layer, "layer_5_text.webp", quality=88)

print("\nDone. Sum of bytes:")
total = sum((OUT / f).stat().st_size for f in OUT.iterdir() if f.suffix == ".webp")
print(f"  Total: {total:,} bytes  (~{total/1024/1024:.1f} MB)")
