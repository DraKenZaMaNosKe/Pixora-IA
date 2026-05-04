"""
Iah Egyptian v2 — Diseño Rueda Zodiacal (sin landscape)

Capas:
  z=0  layer_0_sky          parallax 0.10  → cielo lapis con estrellas
  z=1  layer_1_halo         parallax 0.35  → halo dorado SUTIL (30% alpha)
  z=2  layer_2_moon         parallax 0.55  → la luna
  z=3  layer_3_frame        parallax 0.70  → frame jeroglifico
  z=4  layer_4_zodiac       parallax 0.50  → 12 signos zodiacales en círculo
  z=5  layer_5_text         parallax 1.20  → "Salve · Eduardo · Cuarto Creciente · Tauro · 528 Hz"
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import math, random

ASSETS = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian")
OUT = ASSETS / "parallax_v2"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1080, 2340
MARGIN = int(W * 0.08)
W0, H0 = W + 2*MARGIN, H + 2*MARGIN  # sky layer is bigger than screen


def fit_cover(img, tw, th):
    iw, ih = img.size
    sr, tr = iw/ih, tw/th
    if sr > tr: nh, nw = th, int(th * sr)
    else:       nw, nh = tw, int(tw / sr)
    img = img.resize((nw, nh), Image.LANCZOS)
    return img.crop(((nw-tw)//2, (nh-th)//2, (nw-tw)//2 + tw, (nh-th)//2 + th))


def save_webp(img, name, q=88):
    p = OUT / name
    img.save(p, "WEBP", quality=q, method=6)
    print(f"  {name:30s} {p.stat().st_size:>10,} b")


# ═══ z=0  SKY ════════════════════════════════════════════════════════════════
print("\nlayer_0_sky.webp")
bg = Image.open(ASSETS / "bg_sky_lapis.png").convert("RGBA")
sky = fit_cover(bg, W0, H0)
random.seed(528)
sd = ImageDraw.Draw(sky)
for _ in range(280):
    x = random.randint(0, W0); y = random.randint(0, H0)
    r = random.choice([1,1,1,1,2,2,3])
    a = random.randint(140, 250)
    color = random.choice([(255,255,255,a), (245,214,118,a), (200,220,255,a)])
    sd.ellipse([x-r, y-r, x+r, y+r], fill=color)
save_webp(sky.convert("RGB"), "layer_0_sky.webp", q=82)


# ═══ z=1  HALO MUY SUTIL (alpha 30%) ════════════════════════════════════════
print("layer_1_halo.webp")
halo_src = Image.open(ASSETS / "halo_gold.png").convert("RGBA")
halo_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
halo_size = 920
halo_resized = halo_src.resize((halo_size, halo_size), Image.LANCZOS)

# Lower the alpha to 30% (más transparente como pidió el usuario)
def lower_alpha(img, factor):
    r, g, b, a = img.split()
    a = a.point(lambda v: int(v * factor))
    return Image.merge("RGBA", (r, g, b, a))

halo_transparent = lower_alpha(halo_resized, 0.30)

halo_x, halo_y = (W - halo_size) // 2, 380
# subtle outer glow (also transparent)
glow = halo_transparent.filter(ImageFilter.GaussianBlur(radius=24))
halo_layer.alpha_composite(glow, (halo_x, halo_y))
halo_layer.alpha_composite(halo_transparent, (halo_x, halo_y))
save_webp(halo_layer, "layer_1_halo.webp", q=88)


# ═══ z=2  MOON ══════════════════════════════════════════════════════════════
print("layer_2_moon.webp")
moon_src = Image.open(ASSETS / "moon_d14_full.png").convert("RGBA")
moon_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
moon_size = 600
moon_resized = moon_src.resize((moon_size, moon_size), Image.LANCZOS)
moon_x = (W - moon_size) // 2
moon_y = halo_y + (halo_size - moon_size) // 2
moon_layer.alpha_composite(moon_resized, (moon_x, moon_y))
save_webp(moon_layer, "layer_2_moon.webp", q=88)


# ═══ z=3  FRAME ══════════════════════════════════════════════════════════════
print("layer_3_frame.webp")
frame_src = Image.open(ASSETS / "frame_hieroglyph.png").convert("RGBA")
frame_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
frame_size = 1010
frame_resized = frame_src.resize((frame_size, frame_size), Image.LANCZOS)
frame_x = (W - frame_size) // 2
frame_y = halo_y + (halo_size - frame_size) // 2
frame_layer.alpha_composite(frame_resized, (frame_x, frame_y))
save_webp(frame_layer, "layer_3_frame.webp", q=88)


# ═══ z=4  ZODIAC WHEEL (12 signos rodeando la luna) ═════════════════════════
print("layer_4_zodiac.webp")
zodiac_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
zd = ImageDraw.Draw(zodiac_layer)

# Cargar fuente con soporte unicode zodiac
font_paths = [
    r"C:/Windows/Fonts/seguisym.ttf",   # Segoe UI Symbol — soporta zodiacos
    r"C:/Windows/Fonts/arial.ttf",
    r"C:/Windows/Fonts/georgia.ttf",
]
font_zodiac = font_zodiac_big = None
for fp in font_paths:
    if Path(fp).exists():
        font_zodiac = ImageFont.truetype(fp, 78)
        font_zodiac_big = ImageFont.truetype(fp, 108)
        print(f"  font: {Path(fp).name}")
        break

if font_zodiac is None:
    font_zodiac = font_zodiac_big = ImageFont.load_default()

# 12 signos zodiacales unicode
zodiac_signs = ['♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓']
zodiac_names = ['aries','taurus','gemini','cancer','leo','virgo','libra','scorpio','sagittarius','capricorn','aquarius','pisces']

# El centro del altar (donde está la luna) — los signos giran alrededor
center_x = W // 2
center_y = halo_y + halo_size // 2
radius = 660  # afuera del frame, no encima

# Indice del signo del usuario (Tauro = 1)
USER_SIGN_INDEX = 1  # Tauro

for i, (sign, name) in enumerate(zip(zodiac_signs, zodiac_names)):
    # 12 signos en un círculo, comenzando desde arriba (Aries en top)
    angle = (i / 12) * 2 * math.pi - math.pi / 2  # offset -90° = arriba
    x = center_x + int(radius * math.cos(angle))
    y = center_y + int(radius * math.sin(angle))

    is_user_sign = (i == USER_SIGN_INDEX)
    if is_user_sign:
        # Tauro brilla más fuerte (gold bright + glow)
        font = font_zodiac_big
        color_glow = (245, 214, 118, 80)
        color_main = (245, 214, 118, 255)
        glow_radius = 14
    else:
        font = font_zodiac
        color_glow = (212, 175, 55, 35)
        color_main = (212, 175, 55, 200)
        glow_radius = 6

    # Centrar el caracter
    bbox = zd.textbbox((0, 0), sign, font=font)
    char_w = bbox[2] - bbox[0]
    char_h = bbox[3] - bbox[1]
    px, py = x - char_w // 2, y - char_h // 2

    # Glow halo
    for dx in range(-glow_radius, glow_radius+1, 2):
        for dy in range(-glow_radius, glow_radius+1, 2):
            if dx*dx + dy*dy <= glow_radius*glow_radius:
                zd.text((px+dx, py+dy), sign, font=font, fill=color_glow)
    # Main glyph
    zd.text((px, py), sign, font=font, fill=color_main)

save_webp(zodiac_layer, "layer_4_zodiac.webp", q=92)


# ═══ z=5  TEXT (sin landscape, texto sube) ══════════════════════════════════
print("layer_5_text.webp")
text_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
td = ImageDraw.Draw(text_layer)
try:
    fp = r"C:/Windows/Fonts/georgia.ttf"
    font_big = ImageFont.truetype(fp, 100)
    font_med = ImageFont.truetype(fp, 42)
    font_sm  = ImageFont.truetype(fp, 26)
    font_xs  = ImageFont.truetype(fp, 22)
except Exception:
    font_big = font_med = font_sm = font_xs = ImageFont.load_default()


def text_with_glow(draw, pos, text, font, fill, glow_color, glow_radius=8):
    x, y = pos
    for dx in range(-glow_radius, glow_radius+1, 2):
        for dy in range(-glow_radius, glow_radius+1, 2):
            if dx*dx + dy*dy <= glow_radius*glow_radius:
                draw.text((x+dx, y+dy), text, font=font, fill=glow_color)
    draw.text(pos, text, font=font, fill=fill)


# Sin landscape, el texto puede vivir más cómodo en el tercio inferior.
# Lo posicionamos centrado abajo del altar.
text_y_start = int(H * 0.74)

greet = "𓂀  Caballero de Tauro  𓂀"
bbox = td.textbbox((0, 0), greet, font=font_xs)
gw = bbox[2] - bbox[0]
td.text(((W - gw) // 2, text_y_start), greet, font=font_xs, fill=(200, 152, 96, 220))

name = "Eduardo"
bbox = td.textbbox((0, 0), name, font=font_big)
nw = bbox[2] - bbox[0]
text_with_glow(td, ((W - nw) // 2, text_y_start + 50), name, font_big,
               fill=(245, 214, 118, 255), glow_color=(212, 175, 55, 35),
               glow_radius=11)

phase = "Cuarto Creciente"
bbox = td.textbbox((0, 0), phase, font=font_med)
pw = bbox[2] - bbox[0]
td.text(((W - pw) // 2, text_y_start + 195), phase, font=font_med, fill=(255, 255, 255, 240))

info = "528 HZ  ·  12 JUN 2026  ·  38% iluminada"
bbox = td.textbbox((0, 0), info, font=font_sm)
iw = bbox[2] - bbox[0]
td.text(((W - iw) // 2, text_y_start + 260), info, font=font_sm, fill=(212, 175, 55, 230))

save_webp(text_layer, "layer_5_text.webp", q=88)

print("\n=== Total ===")
total = sum((OUT / f).stat().st_size for f in OUT.iterdir() if f.suffix == ".webp")
print(f"  Total: {total:,} bytes  (~{total/1024/1024:.2f} MB)")

print("\n=== Composite preview ===")
# Generar una vista previa compositada igual que en el mockup
preview = Image.new("RGBA", (W, H), (10, 14, 58, 255))
preview = Image.alpha_composite(preview, fit_cover(sky, W, H).convert("RGBA"))
for layer_name in ['layer_1_halo.webp', 'layer_2_moon.webp', 'layer_3_frame.webp',
                   'layer_4_zodiac.webp', 'layer_5_text.webp']:
    layer = Image.open(OUT / layer_name).convert("RGBA")
    preview = Image.alpha_composite(preview, layer)
preview_rgb = preview.convert("RGB")
preview_rgb.save(OUT / "preview_composite.webp", "WEBP", quality=88)
preview_rgb.resize((540, 1170), Image.LANCZOS).save(
    OUT / "preview_composite_thumb.webp", "WEBP", quality=72)
print(f"  preview_composite.webp        {(OUT/'preview_composite.webp').stat().st_size:>10,} b")
print(f"  preview_composite_thumb.webp  {(OUT/'preview_composite_thumb.webp').stat().st_size:>10,} b")
