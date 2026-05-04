"""
Iah Egyptian v3 — Rueda Zodiacal AJUSTADA + Background Cosmic Real

Cambios respecto a v2:
  · Sky bg = fondo_ancho.webp (2002x4322, real cosmic Egyptian scene)
  · Zodiac radius 660 → 440 px (los 12 signos AHORA SÍ caben en pantalla)
  · Tauro highlight más sutil (no tan gigante)
  · Parallax factors agresivos para que el efecto se sienta REAL:
      sky    0.05  (casi estático = profundidad infinita)
      halo   0.30
      moon   0.50
      frame  0.70
      zodiac 0.90  ← se mueve mucho con el gyro
      text   1.60  ← float frontal extremo
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import math

ASSETS = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian")
OUT = ASSETS / "parallax_v3"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1080, 2340  # pantalla


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


# ═══ z=0  SKY (nueva imagen Gemini, ya tiene 2002x4322 perfectos) ═══════════
print("\nlayer_0_sky.webp (using fondo_ancho — Gemini cosmic scene)")
sky_src = Image.open(ASSETS / "fondo_ancho.webp").convert("RGBA")
print(f"  source: {sky_src.size[0]}x{sky_src.size[1]}")
# La imagen ya es 2002x4322 (1.85x pantalla). Para parallax queremos
# darle la misma altura que el área de pantalla + margen, así que
# scaleamos a 1.4x pantalla = 1512x3276 para que pese menos pero
# siga teniendo margen para el gyro.
TARGET_W, TARGET_H = 1512, 3276
sky_resized = fit_cover(sky_src, TARGET_W, TARGET_H)
save_webp(sky_resized.convert("RGB"), "layer_0_sky.webp", q=88)


# Geometría compartida para que todas las capas se alineen:
ALTAR_CENTER_X = W // 2
ALTAR_CENTER_Y = 760            # centro vertical del altar
HALO_SIZE      = 760            # antes 920
FRAME_SIZE     = 720             # antes 1010 — más chico para que no tape el zodiaco
MOON_SIZE      = 460             # antes 600
ZODIAC_RADIUS  = 470             # los 12 signos VISIBLES y FUERA del frame
ZODIAC_FONT    = 60              # antes 64
ZODIAC_USER_FONT = 80            # antes 84


# ═══ z=1  HALO sutil (alpha 30%) ═════════════════════════════════════════════
print("\nlayer_1_halo.webp")
halo_src = Image.open(ASSETS / "halo_gold.png").convert("RGBA")
halo_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
halo_resized = halo_src.resize((HALO_SIZE, HALO_SIZE), Image.LANCZOS)


def lower_alpha(img, factor):
    r, g, b, a = img.split()
    a = a.point(lambda v: int(v * factor))
    return Image.merge("RGBA", (r, g, b, a))


halo_transparent = lower_alpha(halo_resized, 0.30)
halo_x = ALTAR_CENTER_X - HALO_SIZE // 2
halo_y = ALTAR_CENTER_Y - HALO_SIZE // 2
# SIN GLOW — el usuario pidió quitarlo (no se veía bien)
halo_layer.alpha_composite(halo_transparent, (halo_x, halo_y))
save_webp(halo_layer, "layer_1_halo.webp", q=88)


# ═══ z=2  MOON ══════════════════════════════════════════════════════════════
print("\nlayer_2_moon.webp")
moon_src = Image.open(ASSETS / "moon_d14_full.png").convert("RGBA")
moon_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
moon_resized = moon_src.resize((MOON_SIZE, MOON_SIZE), Image.LANCZOS)
moon_x = ALTAR_CENTER_X - MOON_SIZE // 2
moon_y = ALTAR_CENTER_Y - MOON_SIZE // 2
moon_layer.alpha_composite(moon_resized, (moon_x, moon_y))
save_webp(moon_layer, "layer_2_moon.webp", q=88)


# ═══ z=3  FRAME ══════════════════════════════════════════════════════════════
print("\nlayer_3_frame.webp")
frame_src = Image.open(ASSETS / "frame_hieroglyph.png").convert("RGBA")
frame_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
frame_resized = frame_src.resize((FRAME_SIZE, FRAME_SIZE), Image.LANCZOS)
frame_x = ALTAR_CENTER_X - FRAME_SIZE // 2
frame_y = ALTAR_CENTER_Y - FRAME_SIZE // 2
frame_layer.alpha_composite(frame_resized, (frame_x, frame_y))
save_webp(frame_layer, "layer_3_frame.webp", q=88)


# ═══ z=4  ZODIAC WHEEL (radius=470, FUERA del frame, CABE en pantalla) ══════
print("\nlayer_4_zodiac.webp (radius=470, fuera del frame de 720)")
zodiac_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
zd = ImageDraw.Draw(zodiac_layer)

font_paths = [r"C:/Windows/Fonts/seguisym.ttf", r"C:/Windows/Fonts/arial.ttf"]
font_zodiac = font_zodiac_big = None
for fp in font_paths:
    if Path(fp).exists():
        font_zodiac = ImageFont.truetype(fp, ZODIAC_FONT)
        font_zodiac_big = ImageFont.truetype(fp, ZODIAC_USER_FONT)
        break
if font_zodiac is None:
    font_zodiac = font_zodiac_big = ImageFont.load_default()

zodiac_signs = ['♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓']
USER_SIGN_INDEX = 1  # Tauro

for i, sign in enumerate(zodiac_signs):
    angle = (i / 12) * 2 * math.pi - math.pi / 2  # Aries arriba (12 oclock)
    x = ALTAR_CENTER_X + int(ZODIAC_RADIUS * math.cos(angle))
    y = ALTAR_CENTER_Y + int(ZODIAC_RADIUS * math.sin(angle))

    is_user = (i == USER_SIGN_INDEX)
    if is_user:
        font = font_zodiac_big
        color_glow = (245, 214, 118, 90)
        color_main = (245, 214, 118, 255)
        glow_radius = 12
    else:
        font = font_zodiac
        color_glow = (212, 175, 55, 30)
        color_main = (212, 175, 55, 200)
        glow_radius = 5

    bbox = zd.textbbox((0, 0), sign, font=font)
    cw = bbox[2] - bbox[0]
    ch = bbox[3] - bbox[1]
    px, py = x - cw // 2, y - ch // 2

    for dx in range(-glow_radius, glow_radius+1, 2):
        for dy in range(-glow_radius, glow_radius+1, 2):
            if dx*dx + dy*dy <= glow_radius*glow_radius:
                zd.text((px+dx, py+dy), sign, font=font, fill=color_glow)
    zd.text((px, py), sign, font=font, fill=color_main)

save_webp(zodiac_layer, "layer_4_zodiac.webp", q=92)


# ═══ z=5  TEXT ══════════════════════════════════════════════════════════════
print("\nlayer_5_text.webp")
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


def text_with_glow(d, pos, t, f, fill, gc, gr=8):
    x, y = pos
    for dx in range(-gr, gr+1, 2):
        for dy in range(-gr, gr+1, 2):
            if dx*dx + dy*dy <= gr*gr:
                d.text((x+dx, y+dy), t, font=f, fill=gc)
    d.text(pos, t, font=f, fill=fill)


text_y_start = int(H * 0.78)  # más abajo, debajo del zodiaco completo
greet = "𓂀  Caballero de Tauro  𓂀"
bbox = td.textbbox((0, 0), greet, font=font_xs)
gw = bbox[2] - bbox[0]
td.text(((W - gw) // 2, text_y_start), greet, font=font_xs, fill=(200, 152, 96, 220))

name = "Eduardo"
bbox = td.textbbox((0, 0), name, font=font_big)
nw = bbox[2] - bbox[0]
text_with_glow(td, ((W - nw) // 2, text_y_start + 50), name, font_big,
               (245, 214, 118, 255), (212, 175, 55, 35), 11)

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

# Generate composite preview
print("\n=== Composite preview ===")
preview = Image.new("RGBA", (W, H), (10, 14, 58, 255))
sky_for_preview = fit_cover(Image.open(ASSETS / "fondo_ancho.webp").convert("RGBA"), W, H)
preview = Image.alpha_composite(preview, sky_for_preview.convert("RGBA"))
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
