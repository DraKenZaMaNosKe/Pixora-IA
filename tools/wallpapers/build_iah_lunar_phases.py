"""
Iah Egyptian — 8 lunar phases × 12 zodiac signs = 96 wallpaper variants.

Each variant of the panoramic wallpaper carries:
  * Today's moon phase rendered with the appropriate shadow mask, AND
  * The user's zodiac sign IGNITED with a stronger gold glow over the
    rest, making it instantly readable without text.

The Pixora app picks the variant matching (today's phase, user's sign).
Filename: pixora_iah_egyptian_giza_lunar_{phase_key}_{sign_index}.webp
where sign_index is 0..11 (Aries → Pisces).

The Pixora app calculates today's moon phase (Meeus synodic month) and
applies the matching variant. Each variant is the same 4192x1024
cosmic panoramic with the altar baked in at center, but the FULL MOON
in the altar is masked with a black shadow shape to simulate that
phase's illumination pattern.

Phase indices (matches MoonPhaseService keys):
  0 = new           (0% illuminated, dark disc)
  1 = waxing_crescent
  2 = first_quarter (50% lit, right half visible)
  3 = waxing_gibbous
  4 = full          (100% illuminated)
  5 = waning_gibbous
  6 = third_quarter (50% lit, left half visible)
  7 = waning_crescent

Output filename pattern: pixora_iah_egyptian_giza_lunar_{phase_key}.webp
"""
from PIL import Image, ImageDraw
from pathlib import Path
import math

ASSETS = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian")
LAYERS = ASSETS / "parallax_v6"
STATUES = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/iah_statues")
OUT = ASSETS / "panoramic_phases"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 4192, 1024
SCREEN_W = 1080
CENTER_X = W // 2

# 8 phase definitions: (key, illumination 0..1, is_waxing)
# Note: illumination is the FRACTION LIT (1=full, 0=new). Waxing means
# growing toward full — shadow is on the LEFT side. Waning = shrinking,
# shadow on the RIGHT side.
PHASES = [
    ("new",              0.00, True),
    ("waxing_crescent",  0.20, True),
    ("first_quarter",    0.50, True),
    ("waxing_gibbous",   0.78, True),
    ("full",             1.00, True),
    ("waning_gibbous",   0.78, False),
    ("third_quarter",    0.50, False),
    ("waning_crescent",  0.20, False),
]


def fit_height(img: Image.Image, target_h: int) -> Image.Image:
    iw, ih = img.size
    nw = int(iw * (target_h / ih))
    return img.resize((nw, target_h), Image.LANCZOS)


def apply_phase_mask(moon_img: Image.Image, illum: float, waxing: bool) -> Image.Image:
    """Render the moon's lit fraction by building a shadow MASK with
    ellipse + half-disc primitives, then compositing a translucent dark
    layer through it.

    Geometry: the terminator (light/dark boundary) projects as an ellipse
    centered on the moon, with semi-horizontal axis = R * |2*illum - 1|.
      • Full (illum=1): terminator coincides with disc edge → all lit.
      • Gibbous (illum>0.5): terminator extends INTO the dark side, so
        the lit area = lit half + that ellipse.
      • Half (illum=0.5): terminator is a vertical line through center →
        lit area = exact half-disc.
      • Crescent (illum<0.5): terminator extends INTO the lit side, so
        the lit area = lit half MINUS that ellipse (thin sliver on edge).
    """
    if illum >= 0.99:
        return moon_img.copy()
    if illum <= 0.01:
        # New moon — dim the disc to ~12% brightness so it's still faintly visible
        a = moon_img.split()[-1]
        dimmed = Image.eval(moon_img.convert("RGB"), lambda v: int(v * 0.12))
        out = dimmed.convert("RGBA")
        out.putalpha(a)
        return out

    out = moon_img.copy()
    bbox = out.split()[-1].getbbox()
    if not bbox:
        return out
    cx = (bbox[0] + bbox[2]) // 2
    cy = (bbox[1] + bbox[3]) // 2
    radius = (bbox[2] - bbox[0]) // 2
    disc_box = (cx - radius, cy - radius, cx + radius, cy + radius)

    # Shadow MASK: 255 = full shadow, 0 = lit
    mask = Image.new("L", out.size, 0)
    md = ImageDraw.Draw(mask)

    # Start: entire disc in shadow
    md.ellipse(disc_box, fill=255)

    # Carve out lit half-disc (waxing → right; waning → left)
    if waxing:
        # PIL pieslice: 270 = top, 90 = bottom, going clockwise → right half
        md.pieslice(disc_box, 270, 90, fill=0)
    else:
        md.pieslice(disc_box, 90, 270, fill=0)

    # Apply terminator-ellipse adjustment
    ellipse_semi_h = int(radius * abs(2 * illum - 1))
    if ellipse_semi_h > 0:
        e_box = (cx - ellipse_semi_h, cy - radius,
                 cx + ellipse_semi_h, cy + radius)
        if illum > 0.5:
            # GIBBOUS: terminator ellipse adds lit area into the dark side
            md.ellipse(e_box, fill=0)
        else:
            # CRESCENT: terminator ellipse re-shadows part of the lit side
            md.ellipse(e_box, fill=255)
    # illum == 0.5 exactly: perfect half-disc, no adjustment

    # CRITICAL: clip the mask by the moon's actual alpha so the shadow
    # never leaks into transparent corners outside the disc.
    from PIL import ImageChops
    moon_alpha = out.split()[-1]
    mask = ImageChops.multiply(mask, moon_alpha)

    # Build the translucent dark shadow layer (very dark, slight cool tint)
    shadow_alpha = Image.eval(mask, lambda v: int(v * 0.92))  # 92% max
    shadow = Image.new("RGB", out.size, (3, 2, 8)).convert("RGBA")
    shadow.putalpha(shadow_alpha)

    out.alpha_composite(shadow)
    return out


# ── Zodiac sign positions in the altar wheel ──────────────────────────────
# The original altar layers were drawn for a 1080x2340 viewport with the
# zodiac wheel centred at (540, 760) and radius 470. Aries is at the top
# (12 o'clock) and signs go CLOCKWISE through Pisces.
# When we composite the altar into the 4192x1024 panoramic, we scale the
# layers to height H=1024 (factor 1024/2340 ≈ 0.4376), and centre them
# horizontally at CENTER_X=2096. So the zodiac wheel's centre in the final
# panoramic is at:
#   altar_w_scaled = 1080 * (H/2340) = 1080 * 0.4376 ≈ 472
#   altar_x = CENTER_X - altar_w_scaled / 2  (top-left)
#   wheel_cx = altar_x + 540 * (H/2340)  ≈ CENTER_X (since 540 is half of 1080)
#   wheel_cy = 760 * (H/2340) ≈ 332
#   wheel_r  = 470 * (H/2340) ≈ 206

import math as _math
from PIL import ImageFont

# Altar zoom-out: scale the WHOLE altar group (frame, moon, halo, wheel,
# glyphs) to 60% of the panorama height so the entire wheel + signs fit
# comfortably within a single phone-screen viewport with breathing room.
# The cosmic background (constellations) stays at full panorama height.
ALTAR_ZOOM = 0.60
ALTAR_SCALE = (H / 2340) * ALTAR_ZOOM  # ≈ 0.262
ALTAR_H_SCALED = int(H * ALTAR_ZOOM)   # ≈ 614 px tall
ALTAR_Y_OFFSET = (H - ALTAR_H_SCALED) // 2  # vertically centered

WHEEL_CX = CENTER_X
WHEEL_CY = ALTAR_Y_OFFSET + int(760 * ALTAR_SCALE)
# Wheel radius proportional to the new (smaller) altar
WHEEL_R = int(560 * ALTAR_SCALE)

# Try Segoe UI Symbol (Windows) → falls back to Arial Unicode MS
_FONT_CANDIDATES = [
    r"C:/Windows/Fonts/seguisym.ttf",
    r"C:/Windows/Fonts/arial.ttf",
]


def _load_font(size: int) -> ImageFont.FreeTypeFont:
    for fp in _FONT_CANDIDATES:
        if Path(fp).exists():
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()


# Element → RGB color — pumped saturation so they pop against the dark
# starry background. Original gentle pastels got drowned out at viewing
# distance with home apps overlaid.
ELEMENT_RGB = {
    "fire":  (255,  90,  50),  # vibrant coral-red
    "earth": ( 90, 220, 110),  # bright jade
    "air":   (200, 175, 255),  # bright lilac
    "water": ( 60, 210, 240),  # bright sky-cyan
}

# 12 zodiac signs in Aries-first wheel order
ZODIAC = [
    ("♈", "fire"),   # Aries     ♈ 0
    ("♉", "earth"),  # Taurus    ♉ 1
    ("♊", "air"),    # Gemini    ♊ 2
    ("♋", "water"),  # Cancer    ♋ 3
    ("♌", "fire"),   # Leo       ♌ 4
    ("♍", "earth"),  # Virgo     ♍ 5
    ("♎", "air"),    # Libra     ♎ 6
    ("♏", "water"),  # Scorpio   ♏ 7
    ("♐", "fire"),   # Sagit.    ♐ 8
    ("♑", "earth"),  # Capri.    ♑ 9
    ("♒", "air"),    # Aquarius  ♒ 10
    ("♓", "water"),  # Pisces    ♓ 11
]

# Constellation patterns per sign — list of stars (dx, dy) relative to the
# user-sign center, plus list of (i, j) line connections between stars.
# Coords are in panorama pixels at the canvas scale (1024 height altar).
# Designed to fit in roughly 70x70 px around the user sign.
CONSTELLATIONS = {
    0: { # Aries — small triangle (Hamal, Sheratan, Mesarthim)
        "stars": [(-22, -18), (22, -8), (8, 22)],
        "lines": [(0, 1), (1, 2)],
    },
    1: { # Taurus — V of Hyades + Aldebaran
        "stars": [(-26, 8), (-10, -8), (10, -10), (26, 6), (-2, 22)],
        "lines": [(0, 1), (1, 2), (2, 3), (1, 4), (2, 4)],
    },
    2: { # Gemini — Castor & Pollux + bodies
        "stars": [(-22, -22), (22, -16), (28, 18), (-16, 8), (-8, 28)],
        "lines": [(0, 1), (1, 2), (0, 3), (3, 4), (1, 3)],
    },
    3: { # Cancer — faint Y
        "stars": [(0, -22), (-18, 4), (18, 4), (0, 22)],
        "lines": [(0, 1), (0, 2), (1, 3), (2, 3)],
    },
    4: { # Leo — sickle + tail (Regulus prominent)
        "stars": [(-20, -18), (-8, -22), (10, -10), (24, 4), (8, 22)],
        "lines": [(0, 1), (1, 2), (2, 3), (3, 4)],
    },
    5: { # Virgo — Spica + 4 stars
        "stars": [(-22, -10), (-4, -18), (12, -4), (24, 14), (4, 22)],
        "lines": [(0, 1), (1, 2), (2, 3), (3, 4)],
    },
    6: { # Libra — parallelogram (scales)
        "stars": [(-22, -10), (22, -10), (26, 14), (-18, 14)],
        "lines": [(0, 1), (1, 2), (2, 3), (3, 0)],
    },
    7: { # Scorpio — hook (Antares + tail)
        "stars": [(-24, -16), (-6, -8), (10, 0), (22, 12), (12, 26)],
        "lines": [(0, 1), (1, 2), (2, 3), (3, 4)],
    },
    8: { # Sagittarius — teapot asterism
        "stars": [(-22, 4), (-8, -16), (14, -10), (22, 12), (-2, 18)],
        "lines": [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)],
    },
    9: { # Capricorn — horn / triangle
        "stars": [(-22, -12), (24, -4), (4, 24)],
        "lines": [(0, 1), (1, 2), (2, 0)],
    },
    10: { # Aquarius — Y + water
        "stars": [(-20, -18), (4, -10), (20, -16), (-4, 8), (8, 24)],
        "lines": [(0, 1), (1, 2), (1, 3), (3, 4)],
    },
    11: { # Pisces — V (two fish tied)
        "stars": [(-26, -8), (-6, 0), (6, 0), (26, -8), (0, 22)],
        "lines": [(0, 1), (1, 2), (2, 3), (1, 4), (2, 4)],
    },
}


def zodiac_position(sign_index: int) -> tuple[int, int]:
    """Returns (x, y) of zodiac sign at given index (0=Aries, ... 11=Pisces),
    in panoramic image coordinates."""
    angle = (sign_index / 12) * 2 * _math.pi - _math.pi / 2  # -π/2 = top
    x = WHEEL_CX + int(WHEEL_R * _math.cos(angle))
    y = WHEEL_CY + int(WHEEL_R * _math.sin(angle))
    return x, y


# ── Statue sprites (Órbita Lejana — concepto #1) ─────────────────────────
# 12 monster-god statue PNGs already chroma-keyed by user (transparent bg).
# Filenames in zodiac order (Aries-first):
STATUE_FILES = [
    "aries", "tauro", "geminis", "cancer",
    "leo", "virgo", "libra", "escorpion",
    "sagitario", "capricornio", "acuario", "piscis",
]

# 11 orbit positions for the non-user statues (clean wide spread, alternating
# high/low rows left↔right of the central ring). Coords are (x_center,
# y_bottom, target_height) in panoramic 4192x1024 space.
ORBIT_POSITIONS = [
    (320,  520, 280),   # far-left high
    (640,  900, 280),   # left low
    (960,  440, 280),   # left mid-high
    (1280, 920, 280),   # left-near low
    (1580, 460, 280),   # left-near high
    # gap in front-bottom-center for the user god
    (2680, 920, 280),   # right-near low
    (2980, 460, 280),   # right-near high
    (3300, 900, 280),   # right mid low
    (3620, 440, 280),   # right high
    (3920, 880, 280),   # far-right low
    (2096, 280, 220),   # one above ring (small, like a crown)
]

# User god rendering: bigger and anchored bottom-center, in front of ring
USER_X = CENTER_X
USER_BOTTOM = H - 4   # almost touching bottom
USER_HEIGHT = 540     # ~53% of H


def _load_statue(idx: int) -> Image.Image:
    fp = STATUES / f"{STATUE_FILES[idx]}.png"
    img = Image.open(fp).convert("RGBA")
    # Tight-crop to alpha bbox so positioning is predictable
    bbox = img.split()[-1].getbbox()
    if bbox:
        img = img.crop(bbox)
    return img


def _scale_to_height(img: Image.Image, target_h: int) -> Image.Image:
    iw, ih = img.size
    nw = int(iw * (target_h / ih))
    return img.resize((nw, target_h), Image.LANCZOS)


def draw_zodiac_statues(canvas: Image.Image, user_sign_index: int):
    """Composite the 11 non-user god statues in a wide orbit around the
    central ring, plus the user's god statue large and prominent at
    bottom-center. Replaces the old colored-glyph wheel."""
    # Place the 11 non-user statues
    others = [i for i in range(12) if i != user_sign_index]
    for slot_idx, sign_idx in enumerate(others):
        if slot_idx >= len(ORBIT_POSITIONS):
            break
        x_center, y_bottom, target_h = ORBIT_POSITIONS[slot_idx]
        st = _scale_to_height(_load_statue(sign_idx), target_h)
        sw, sh = st.size
        canvas.alpha_composite(st, (x_center - sw // 2, y_bottom - sh))

    # Place the user's god — bigger, front-center
    if 0 <= user_sign_index < 12:
        user_st = _scale_to_height(_load_statue(user_sign_index), USER_HEIGHT)
        sw, sh = user_st.size
        canvas.alpha_composite(user_st, (USER_X - sw // 2, USER_BOTTOM - sh))


def draw_zodiac_wheel(canvas: Image.Image, user_sign_index: int):
    """Legacy renderer kept for reference — DEPRECATED. Use draw_zodiac_statues."""
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)

    # Glyphs purely proportional to altar zoom — no extra multiplier so
    # they read as small "asterisms" around the wheel rather than as the
    # main visual feature. The user's sign still gets a clear size bump.
    glyph_font = _load_font(int(54 * ALTAR_ZOOM))  # ≈ 32
    user_font  = _load_font(int(74 * ALTAR_ZOOM))  # ≈ 44

    # --- Glow + constellation for the user sign first (so glyphs sit on top)
    if 0 <= user_sign_index < 12:
        ux, uy = zodiac_position(user_sign_index)
        air_rgb = ELEMENT_RGB[ZODIAC[user_sign_index][1]]
        # Element-tinted soft halo (concentric)
        for radius, alpha in [(54, 22), (40, 50), (28, 90), (16, 160)]:
            od.ellipse(
                (ux - radius, uy - radius, ux + radius, uy + radius),
                fill=(*air_rgb, alpha),
            )
        # Constellation around the user sign
        cdef = CONSTELLATIONS.get(user_sign_index)
        if cdef:
            star_pts = [(ux + dx, uy + dy) for dx, dy in cdef["stars"]]
            # Lines first (dim)
            for a, b in cdef["lines"]:
                od.line(
                    [star_pts[a], star_pts[b]],
                    fill=(*air_rgb, 180),
                    width=2,
                )
            # Stars on top
            for i, (sx, sy) in enumerate(star_pts):
                r = 3 if i < 2 else 2  # first two = brighter primary stars
                # Outer halo
                od.ellipse(
                    (sx - r - 3, sy - r - 3, sx + r + 3, sy + r + 3),
                    fill=(*air_rgb, 90),
                )
                # Star core white
                od.ellipse(
                    (sx - r, sy - r, sx + r, sy + r),
                    fill=(255, 255, 255, 255),
                )

    # --- All 12 glyphs in their element color
    for i, (glyph, element) in enumerate(ZODIAC):
        cx, cy = zodiac_position(i)
        rgb = ELEMENT_RGB[element]
        is_user = (i == user_sign_index)
        font = user_font if is_user else glyph_font

        # Soft radial dark vignette behind glyph — proportional to the
        # smaller glyph font.
        disc_r = int((34 if is_user else 28) * ALTAR_ZOOM)
        for r, a in [(disc_r,        0),
                     (max(1, disc_r - 4),   40),
                     (max(1, disc_r - 8),   90),
                     (max(1, disc_r - 12), 150),
                     (max(1, disc_r - 16), 200)]:
            if r > 0:
                od.ellipse(
                    (cx - r, cy - r, cx + r, cy + r),
                    fill=(8, 4, 18, a),
                )

        # Centre the glyph using textbbox
        bbox = od.textbbox((0, 0), glyph, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        tx = cx - tw // 2 - bbox[0]
        ty = cy - th // 2 - bbox[1]

        # Outer glow in element color (offset multi-draw for thickness)
        for off in (-3, -2, -1, 1, 2, 3):
            od.text((tx + off, ty), glyph, font=font, fill=(*rgb, 90))
            od.text((tx, ty + off), glyph, font=font, fill=(*rgb, 90))

        # Sharp glyph on top
        if is_user:
            # User: WHITE core for max contrast against the lilac halo
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    od.text((tx + dx, ty + dy), glyph, font=font, fill=(*rgb, 240))
            od.text((tx, ty), glyph, font=font, fill=(255, 255, 255, 255))
        else:
            od.text((tx, ty), glyph, font=font, fill=(*rgb, 255))

    canvas.alpha_composite(overlay)


def draw_user_sign_glow(canvas: Image.Image, sign_index: int):
    """Legacy entry point — defers to the new statues renderer (Órbita Lejana)."""
    if 0 <= sign_index < 12:
        draw_zodiac_statues(canvas, sign_index)


def build_panoramic_for_phase(phase_key: str, illum: float, waxing: bool,
                              sign_index: int = -1):
    """Build one 4192x1024 panoramic. Optional sign_index (0..11) draws an
    extra gold halo over that zodiac glyph in the wheel."""
    canvas = Image.new("RGBA", (W, H), (5, 7, 30, 255))

    # Wide cosmic background (constellations) tiled
    sky_src = Image.open(ASSETS / "fondo_con_constelaciones.webp").convert("RGBA")
    sky = fit_height(sky_src, H)
    sky_w = sky.size[0]
    if sky_w >= W:
        x = (sky_w - W) // 2
        canvas.paste(sky.crop((x, 0, x + W, H)), (0, 0))
    else:
        sky_mirror = sky.transpose(Image.FLIP_LEFT_RIGHT)
        x = (W - sky_w) // 2
        canvas.paste(sky_mirror.crop((sky_w - x, 0, sky_w, H)), (0, 0))
        canvas.paste(sky, (x, 0))
        canvas.paste(sky_mirror.crop((0, 0, W - x - sky_w, H)), (x + sky_w, 0))

    # Altar layers (composited centered, scaled to H=1024)
    # Order: halo → MOON (with phase mask) → frame → zodiac far/mid/near → text
    layer_files = [
        ("layer_1_halo.webp",        None),
        ("layer_2_moon.webp",        (illum, waxing)),  # apply phase mask
        ("layer_3_frame.webp",       None),
        # Zodiac layers removed — now rendered fresh by draw_zodiac_wheel()
        # with element colors per sign + the user's constellation pattern.
        ("layer_7_text.webp",        None),
    ]

    for fn, phase_args in layer_files:
        p = LAYERS / fn
        if not p.exists():
            continue
        layer = Image.open(p).convert("RGBA")
        # Scale altar layers to ALTAR_H_SCALED (60% of H) so they shrink
        # in the panorama, matching the wheel's smaller radius.
        scaled = fit_height(layer, ALTAR_H_SCALED)
        if phase_args is not None:
            scaled = apply_phase_mask(scaled, *phase_args)
        sw, _ = scaled.size
        canvas.alpha_composite(scaled, (CENTER_X - sw // 2, ALTAR_Y_OFFSET))

    # Personalised user-sign halo (drawn last so it sits on top of all layers).
    if 0 <= sign_index < 12:
        draw_user_sign_glow(canvas, sign_index)

    # Save — filename includes sign suffix only when personalised.
    suffix = f"_{sign_index:02d}" if 0 <= sign_index < 12 else ""
    out_path = OUT / f"pixora_iah_egyptian_giza_lunar_{phase_key}{suffix}.webp"
    canvas.convert("RGB").save(out_path, "WEBP", quality=88, method=6)
    return out_path, out_path.stat().st_size


# 12 zodiac signs in order (matches UserProfileService.ZodiacSign + Aries-first
# wheel position). Sign index N -> angle (N/12)*2*pi - pi/2.
ZODIAC_SIGNS = [
    "aries", "taurus", "gemini", "cancer",
    "leo", "virgo", "libra", "scorpio",
    "sagittarius", "capricorn", "aquarius", "pisces",
]


def main():
    print(f"Building {len(PHASES)} phases x {len(ZODIAC_SIGNS)} signs = "
          f"{len(PHASES) * len(ZODIAC_SIGNS)} variants\n")
    total = 0
    n = 0
    for key, illum, waxing in PHASES:
        for idx, sign in enumerate(ZODIAC_SIGNS):
            path, size = build_panoramic_for_phase(key, illum, waxing, idx)
            total += size
            n += 1
        print(f"  {key:20s} done all 12 signs (~{size//1024} KB each)")
    print(f"\nTotal: {total:,} bytes ({total / 1024 / 1024:.2f} MB)")
    print(f"Files: {OUT}")


if __name__ == "__main__":
    main()
