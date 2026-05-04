"""
Iah Egyptian v6 — Constelaciones cósmicas + Zodiac 3D depth (3 capas).

Listo para correr CUANDO el usuario tenga la nueva imagen Gemini guardada en:
  C:/Users/lalo/OneDrive/Escritorio/wallpapers/tmp/cosmic_zodiac_bg.png  (o .webp)

Capas finales:
  z=0  layer_0_sky          parallax 0.05  → cosmos super wide con constelaciones
  z=1  layer_1_halo         parallax 0.50  → halo dorado (sin glow)
  z=2  layer_2_moon         parallax 0.50  → luna
  z=3  layer_3_frame        parallax 0.50  → frame jeroglifico
  z=4  layer_4_zodiac_far   parallax 0.85  → 4 signos lejanos (chicos, opacos)
  z=5  layer_5_zodiac_mid   parallax 1.20  → 4 signos medios
  z=6  layer_6_zodiac_near  parallax 1.55  → 4 signos cercanos (grandes, brillantes)
                                              ← TAURO va aquí (signo del usuario)
  z=7  layer_7_text         parallax 1.90  → texto Eduardo
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math

ASSETS = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian")
OUT = ASSETS / "parallax_v6"
OUT.mkdir(parents=True, exist_ok=True)

# Buscar nuevo bg en tmp del usuario
NEW_BG_CANDIDATES = [
    # Prefer la version ya copiada al repo (webp más liviano)
    ASSETS / "fondo_con_constelaciones.webp",
    ASSETS / "fondo_con_constelaciones.png",
    Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/tmp/fondo_con_constelaciones.webp"),
    Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/tmp/fondo_con_constelaciones.png"),
    Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/tmp/cosmic_zodiac_bg.png"),
    Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/tmp/cosmic_zodiac_bg.webp"),
]
NEW_BG = next((p for p in NEW_BG_CANDIDATES if p.exists()), None)
if NEW_BG is None:
    print("⚠ Nueva imagen aún no está. Buscando en:")
    for c in NEW_BG_CANDIDATES:
        print(f"  - {c}")
    print("Cuando la tengas guardada con uno de esos nombres, vuelve a correr este script.")
    raise SystemExit(0)
print(f"✓ Usando nuevo bg: {NEW_BG.name}")

W, H = 1080, 2340

# Geometría compartida
ALTAR_CENTER_X = W // 2
ALTAR_CENTER_Y = 720
HALO_SIZE      = 720
FRAME_SIZE     = 680
MOON_SIZE      = 440
ZODIAC_RADIUS  = 460   # un poco más adentro que v3, para que no se corten


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


# ═══ z=0  SKY — nueva imagen Gemini wide cosmic-zodiac ═══════════════════════
print("\nlayer_0_sky.webp — usando nueva imagen Gemini")
sky_src = Image.open(NEW_BG).convert("RGBA")
print(f"  source: {sky_src.size[0]}x{sky_src.size[1]}")
# Mantener aspecto wide. Si es 3240x2340 perfecto. Si no, scale-fit a 3240x2340
if sky_src.size[0] != 3240 or sky_src.size[1] != 2340:
    print(f"  resizing to 3240x2340 (cover-fit)")
    sky_src = fit_cover(sky_src, 3240, 2340)
save_webp(sky_src.convert("RGB"), "layer_0_sky.webp", q=86)


# ═══ z=1  HALO sutil sin glow ═══════════════════════════════════════════════
print("layer_1_halo.webp")
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
halo_layer.alpha_composite(halo_transparent, (halo_x, halo_y))
save_webp(halo_layer, "layer_1_halo.webp", q=88)


# ═══ z=2  MOON ══════════════════════════════════════════════════════════════
print("layer_2_moon.webp")
moon_src = Image.open(ASSETS / "moon_d14_full.png").convert("RGBA")
moon_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
moon_resized = moon_src.resize((MOON_SIZE, MOON_SIZE), Image.LANCZOS)
moon_x = ALTAR_CENTER_X - MOON_SIZE // 2
moon_y = ALTAR_CENTER_Y - MOON_SIZE // 2
moon_layer.alpha_composite(moon_resized, (moon_x, moon_y))
save_webp(moon_layer, "layer_2_moon.webp", q=88)


# ═══ z=3  FRAME ══════════════════════════════════════════════════════════════
print("layer_3_frame.webp")
frame_src = Image.open(ASSETS / "frame_hieroglyph.png").convert("RGBA")
frame_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
frame_resized = frame_src.resize((FRAME_SIZE, FRAME_SIZE), Image.LANCZOS)
frame_x = ALTAR_CENTER_X - FRAME_SIZE // 2
frame_y = ALTAR_CENTER_Y - FRAME_SIZE // 2
frame_layer.alpha_composite(frame_resized, (frame_x, frame_y))
save_webp(frame_layer, "layer_3_frame.webp", q=88)


# ═══ z=4-6  ZODIAC 3D DEPTH ═════════════════════════════════════════════════
# Distribución por profundidad — los signos opuestos en el círculo van en la
# misma capa para que el efecto 3D sea simétrico.
ZODIAC_GROUPS = {
    'far': {  # Lejos: chicos, opaco. Norte/Este (atrás)
        'indices': [0, 3, 6, 9],   # Aries, Cáncer, Libra, Capricornio
        'font_size': 50,
        'glow_alpha': 25,
        'main_alpha': 160,
        'glow_radius': 4,
    },
    'mid': {  # Medio: tamaño normal
        'indices': [2, 5, 8, 11],  # Géminis, Virgo, Sagitario, Piscis
        'font_size': 64,
        'glow_alpha': 35,
        'main_alpha': 210,
        'glow_radius': 7,
    },
    'near': {  # Cerca: grandes, brillantes (Tauro va aquí)
        'indices': [1, 4, 7, 10],  # Tauro, Leo, Escorpio, Acuario
        'font_size': 80,
        'glow_alpha': 90,
        'main_alpha': 255,
        'glow_radius': 14,
    },
}
ZODIAC_SIGNS = ['♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '♓']
USER_SIGN_INDEX = 1  # Tauro

font_paths = [r"C:/Windows/Fonts/seguisym.ttf", r"C:/Windows/Fonts/arial.ttf"]
font_path = next((p for p in font_paths if Path(p).exists()), None)


def render_zodiac_layer(group_key, params, name):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(font_path, params['font_size']) if font_path else ImageFont.load_default()
    user_font = ImageFont.truetype(font_path, params['font_size'] + 24) if font_path else font

    for i in params['indices']:
        sign = ZODIAC_SIGNS[i]
        angle = (i / 12) * 2 * math.pi - math.pi / 2
        x = ALTAR_CENTER_X + int(ZODIAC_RADIUS * math.cos(angle))
        y = ALTAR_CENTER_Y + int(ZODIAC_RADIUS * math.sin(angle))

        is_user = (i == USER_SIGN_INDEX)
        f = user_font if is_user else font
        glow_a = params['glow_alpha'] + (40 if is_user else 0)
        main_a = params['main_alpha']
        gr = params['glow_radius'] + (4 if is_user else 0)

        bbox = d.textbbox((0, 0), sign, font=f)
        cw = bbox[2] - bbox[0]
        ch = bbox[3] - bbox[1]
        px, py = x - cw // 2, y - ch // 2

        for dx in range(-gr, gr+1, 2):
            for dy in range(-gr, gr+1, 2):
                if dx*dx + dy*dy <= gr*gr:
                    d.text((px+dx, py+dy), sign, font=f, fill=(245, 214, 118, glow_a))
        d.text((px, py), sign, font=f, fill=(245, 214, 118, main_a))

    save_webp(layer, name, q=92)


print("layer_4_zodiac_far.webp — 4 signos lejanos chicos opacos")
render_zodiac_layer('far',  ZODIAC_GROUPS['far'],  "layer_4_zodiac_far.webp")
print("layer_5_zodiac_mid.webp — 4 signos medios")
render_zodiac_layer('mid',  ZODIAC_GROUPS['mid'],  "layer_5_zodiac_mid.webp")
print("layer_6_zodiac_near.webp — 4 signos cercanos brillantes (incluye Tauro)")
render_zodiac_layer('near', ZODIAC_GROUPS['near'], "layer_6_zodiac_near.webp")


# ═══ z=7  TEXT ══════════════════════════════════════════════════════════════
print("\nlayer_7_text.webp")
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


text_y_start = int(H * 0.78)
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

save_webp(text_layer, "layer_7_text.webp", q=88)

print("\n=== Total ===")
total = sum((OUT / f).stat().st_size for f in OUT.iterdir() if f.suffix == ".webp")
print(f"  Total: {total:,} bytes  (~{total/1024/1024:.2f} MB)")

# Generar composite preview (con sky cropped a 1080x2340 center)
print("\n=== Composite preview ===")
sky_for_preview = fit_cover(Image.open(NEW_BG).convert("RGBA"), W, H)
preview = Image.alpha_composite(Image.new("RGBA", (W, H), (10, 14, 58, 255)),
                                  sky_for_preview.convert("RGBA"))
for layer_name in ['layer_1_halo.webp', 'layer_2_moon.webp', 'layer_3_frame.webp',
                   'layer_4_zodiac_far.webp', 'layer_5_zodiac_mid.webp',
                   'layer_6_zodiac_near.webp', 'layer_7_text.webp']:
    layer = Image.open(OUT / layer_name).convert("RGBA")
    preview = Image.alpha_composite(preview, layer)
preview_rgb = preview.convert("RGB")
preview_rgb.save(OUT / "preview_composite.webp", "WEBP", quality=88)
preview_rgb.resize((540, 1170), Image.LANCZOS).save(
    OUT / "preview_composite_thumb.webp", "WEBP", quality=72)
print(f"  preview_composite.webp        {(OUT/'preview_composite.webp').stat().st_size:>10,} b")
print(f"  preview_composite_thumb.webp  {(OUT/'preview_composite_thumb.webp').stat().st_size:>10,} b")
