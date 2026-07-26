"""Genera 4 mockups (frames de referencia) para el video de TikTok de Pixora,
usando los wallpapers rig reales dentro de teléfonos idealizados. Son la
referencia visual para que Grok anime los clips + guía de layout para CapCut.
"""
import io, sys, urllib.request, time
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import json
PUBROOT = "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public"
PUB = f"{PUBROOT}/wallpaper-images"
OUT = Path(r"C:/Users/lalo/Desktop/VIDEO_TIKTOK_MOCKUPS"); OUT.mkdir(parents=True, exist_ok=True)
QR = Path(r"C:/Users/lalo/Desktop/PRUEBA_TONOS_LIMPIOS/pixora_qr_playstore.png")
W, H = 1080, 1920

def dl_url(url):
    return Image.open(io.BytesIO(urllib.request.urlopen(f"{url}?nc={int(time.time())}", timeout=30).read())).convert("RGB")
def dl(sid):
    return dl_url(f"{PUB}/{sid}.webp")

# Los 3 rig (flats grandes) para hero/acción/cta
wp = {"delfines": dl("delfines_santuario_luz"), "astro": dl("astronauta_nebula_flota"), "heroina": dl("heroina_candy_mecha_rig_v1")}

# Variedad: bajar previews de varios wallpapers publicados del catálogo
variety = []
try:
    idx = json.loads(urllib.request.urlopen(f"{PUB}/catalog_index.json?nc={int(time.time())}", timeout=25).read())
    for it in idx.get("items", []):
        u = it.get("preview_url") or it.get("image_url")
        if u and it.get("published") is not False:
            try: variety.append(dl_url(u));
            except Exception: pass
        if len(variety) >= 12: break
except Exception as e:
    print("catalog fetch:", e)
if len(variety) < 6:  # fallback: usa los rig
    variety += [wp["delfines"], wp["astro"], wp["heroina"]]
print(f"variedad: {len(variety)} wallpapers del catálogo")

def font(sz, bold=True):
    for n in (["arialbd.ttf", "ariblk.ttf"] if bold else ["arial.ttf"]):
        try: return ImageFont.truetype(n, sz)
        except Exception: pass
    return ImageFont.load_default()

def rounded(img, rad):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.size[0], img.size[1]], rad, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0)); out.paste(img, (0, 0), m); return out

def cover(img, w, h):
    s = max(w / img.width, h / img.height)
    r = img.resize((int(img.width * s), int(img.height * s)), Image.LANCZOS)
    return r.crop(((r.width - w) // 2, (r.height - h) // 2, (r.width - w) // 2 + w, (r.height - h) // 2 + h))

def phone(wpimg, pw, ph):
    """teléfono: wallpaper cover + marco redondeado + borde neón."""
    screen = rounded(cover(wpimg, pw - 24, ph - 24), 60)
    body = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([0, 0, pw, ph], 74, fill=(12, 12, 20, 255))
    body.paste(screen, (12, 12), screen)
    return body

def bg_gradient(top, bot):
    b = Image.new("RGB", (W, H), top)
    d = ImageDraw.Draw(b)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return b

def glow_behind(base, ph_img, pos, color):
    g = Image.new("RGBA", base.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    cx, cy = pos[0] + ph_img.width // 2, pos[1] + ph_img.height // 2
    gd.ellipse([cx - ph_img.width, cy - ph_img.height // 2, cx + ph_img.width, cy + ph_img.height // 2], fill=color)
    g = g.filter(ImageFilter.GaussianBlur(120))
    base.paste(Image.alpha_composite(base.convert("RGBA"), g).convert("RGB"), (0, 0))

def text_center(d, cy, txt, fnt, fill=(255, 255, 255), shadow=(0, 0, 0)):
    w = d.textlength(txt, font=fnt)
    x = (W - w) / 2
    d.text((x + 4, cy + 4), txt, font=fnt, fill=shadow)
    d.text((x, cy), txt, font=fnt, fill=fill)

# ── Frame 1: HOOK ──
f = bg_gradient((8, 6, 28), (20, 8, 40)).convert("RGBA")
ph = phone(wp["delfines"], 560, 1140)
pos = ((W - 560) // 2, 470)
glow_behind(f, ph, pos, (60, 180, 255, 110))
f.paste(ph, pos, ph)
d = ImageDraw.Draw(f)
text_center(d, 150, "Tu pantalla merece", font(78))
text_center(d, 250, "VIDA", font(130), fill=(90, 220, 255))
text_center(d, 400, "3D LIVE WALLPAPERS", font(44), fill=(200, 220, 255))
f.convert("RGB").save(OUT / "frame1_hook.png")

# ── Frame 2: ACCIÓN ──
f = bg_gradient((12, 8, 30), (30, 10, 44)).convert("RGBA")
ph = phone(wp["heroina"], 540, 1100); pos = ((W - 540) // 2, 300)
glow_behind(f, ph, pos, (255, 60, 150, 100))
f.paste(ph, pos, ph)
# 2 miniaturas abajo (del catálogo, para mostrar que hay más)
for i, im in enumerate((variety + [wp["delfines"], wp["astro"]])[:2]):
    mini = rounded(cover(im, 240, 420), 34)
    f.paste(mini, (150 + i * 480, 1460), mini)
d = ImageDraw.Draw(f)
text_center(d, 150, "Elige · Aplica · Listo", font(74))
f.convert("RGB").save(OUT / "frame2_accion.png")

# ── Frame 3: VARIEDAD (grid del catálogo real) ──
f = bg_gradient((6, 6, 24), (18, 10, 38)).convert("RGBA")
d = ImageDraw.Draw(f)
cols, rows, tw, th, gap = 3, 3, 300, 420, 20
gw = cols * tw + (cols - 1) * gap
gx0, gy0 = (W - gw) // 2, 560
grid_imgs = (variety * 3)[:cols * rows]
for i, im in enumerate(grid_imgs):
    r, c = divmod(i, cols)
    mini = rounded(cover(im, tw, th), 28)
    f.paste(mini, (gx0 + c * (tw + gap), gy0 + r * (th + gap)), mini)
text_center(d, 160, "Cientos de fondos", font(72))
text_center(d, 260, "VIVOS · 3D & 4K", font(88), fill=(120, 230, 255))
f.convert("RGB").save(OUT / "frame3_variedad.png")

# ── Frame 4: CTA + QR ──
f = bg_gradient((10, 8, 30), (24, 10, 46)).convert("RGBA")
ph = phone(wp["astro"], 470, 950); pos = ((W - 470) // 2, 210)
glow_behind(f, ph, pos, (120, 90, 255, 110))
f.paste(ph, pos, ph)
d = ImageDraw.Draw(f)
text_center(d, 1210, "Descárgala GRATIS", font(72))
# QR
qr = Image.open(QR).convert("RGB").resize((360, 360), Image.NEAREST)
qrbox = Image.new("RGB", (400, 400), (255, 255, 255)); qrbox.paste(qr, (20, 20))
f.paste(qrbox, ((W - 400) // 2, 1320))
text_center(d, 1760, "Busca: Fondos de pantalla - Pixora IA", font(46))
f.convert("RGB").save(OUT / "frame4_cta.png")

print("[OK] 4 mockups en", OUT)
for p in sorted(OUT.glob("*.png")): print("  ", p.name)
