"""Upload Morrigan (Darkstalkers) canvas_scene to Pixora.

Pattern: follows the "fórmula mágica" validated with ryu_hadouken on 2026-06-29
— every subject image_layer is baked into a 1080x2340 canvas with the subject
pre-positioned, and the spec keeps scale=1.0/offset=0. Cover-fit of the
device surface only crops top/bottom on shorter screens (Huawei 1080x1920);
the subject NEVER shifts laterally between devices.

Asset structure (source: C:/Users/lalo/Desktop/wallPapers_repo/nuevos/darkstalkers/):
- fondo_morrigan.png            -> full background (1080x1920, opaque)
- morrigan_sola_.png            -> Morrigan body, transparent BG (1080x1920)
- cabello_frame_00..06.png      -> 6 hair frames (00,01,02,03,04,06 — 05 missing
                                  in source; loop will still feel smooth)
- morrigan_wallpaper_estatico.png -> composited final, used for the STATIC tab
                                  (separate upload, not this scene)

Animation: cycles primitive (v1.7.41) — 6 image_layers `cabello_00..06`,
time-multiplexed via a single `cabello_swing` cycle of duration_s=1.0,
each frame visible ~167ms. Loops forever, no triggers needed.
"""
import re
import json
import shutil
import sys
import urllib.request
from io import BytesIO
from pathlib import Path
from PIL import Image

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/darkstalkers")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_morrigan_darkstalkers")

PROJECT  = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET   = "wallpaper-images"  # also hosts <scene>_preview.webp (see _upload_ryu_hadouken.py)
SCENE_BUCKET = "wallpaper-scenes"

SCENE_ID = "morrigan_darkstalkers"
TARGET = (1080, 2340)
SRC_WH = (1080, 1920)

# Frames available (note: 05 is missing from source — we loop 00->01->02->03->04->06)
HAIR_FRAMES = ["00", "01", "02", "03", "04", "06"]
HAIR_CYCLE_DURATION_S = 1.0  # full loop ~1s -> 167ms per frame, smooth swing

# ------------------------------------------------------------------ helpers
def pad_to_target(im: Image.Image) -> Image.Image:
    """Pad a 1080x1920 image vertically (centered) into a 1080x2340 canvas.

    Transparent padding for layers with alpha (cabello, morrigan_sola), so
    the subject keeps its proportional vertical position and the renderer
    can blend cleanly. Background image (no alpha) gets centered against
    a black canvas; cover-fit of the surface will hide the bands on most
    devices (Samsung shows the full bitmap, Huawei crops top/bottom of
    TARGET which is exactly where the padding lives — invisible)."""
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    sw, sh = im.size
    tw, th = TARGET
    if (sw, sh) == TARGET:
        return im
    canvas = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    x = (tw - sw) // 2
    y = (th - sh) // 2
    canvas.alpha_composite(im, (x, y))
    return canvas


def save_webp(im: Image.Image, out: Path, quality=92):
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out, "WEBP", quality=quality, method=6)


def supabase_put(bucket: str, key: str, body: bytes, content_type: str, sk: str):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{key}",
        data=body, method="PUT",
        headers={
            "Authorization": f"Bearer {sk}",
            "apikey": sk,
            "Content-Type": content_type,
            "x-upsert": "true",
            "Cache-Control": "no-cache, max-age=0",
        }
    )
    return urllib.request.urlopen(req)


# ------------------------------------------------------------------ main
def main():
    keys_md = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}", keys_md)[0]

    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)

    # Verify source files
    required = ["fondo_morrigan.png", "morrigan_sola_.png"] + \
               [f"cabello_frame_{n}.png" for n in HAIR_FRAMES]
    missing = [r for r in required if not (SRC / r).exists()]
    if missing:
        print(f"ERROR — missing source files: {missing}", file=sys.stderr)
        sys.exit(1)

    # ---- 1. Bake fondo (COVER-FIT) ------------------------------------
    # Background MUST be cover-fit, NOT padded — padding with black creates
    # visible bands on devices whose surface matches TARGET exactly (Samsung
    # A155M 1080x2340 = TARGET, so the bands show). Cover-fit scales the
    # source to fill TARGET and crops the horizontal/vertical excess so
    # there's never empty space. Subjects (morrigan, hair frames) DO use
    # pad_to_target() because they have transparent alpha — padding them
    # keeps their proportional position and the renderer composites cleanly.
    print("[1/4] Baking fondo (cover-fit, no padding bands)...")
    fondo = Image.open(SRC / "fondo_morrigan.png").convert("RGB")
    tw, th = TARGET
    sw, sh = fondo.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(round(sw * scale)), int(round(sh * scale))
    resized = fondo.resize((nw, nh), Image.LANCZOS)
    cx, cy = (nw - tw) // 2, (nh - th) // 2
    fondo_cf = resized.crop((cx, cy, cx + tw, cy + th))
    out_fondo = WORK / f"{SCENE_ID}_fondo.webp"
    fondo_cf.save(out_fondo, "WEBP", quality=92, method=6)
    print(f"      -> {out_fondo.name} ({out_fondo.stat().st_size:,} bytes)")

    # ---- 2. Bake morrigan ---------------------------------------------
    print("[2/4] Baking morrigan...")
    morrigan = Image.open(SRC / "morrigan_sola_.png")
    morrigan_baked = pad_to_target(morrigan)
    out_morrigan = WORK / f"{SCENE_ID}_morrigan.webp"
    save_webp(morrigan_baked, out_morrigan)
    print(f"      -> {out_morrigan.name} ({out_morrigan.stat().st_size:,} bytes)")

    # ---- 3. Bake each hair frame --------------------------------------
    print(f"[3/4] Baking {len(HAIR_FRAMES)} hair frames...")
    hair_outputs = []
    for idx, n in enumerate(HAIR_FRAMES):
        src = SRC / f"cabello_frame_{n}.png"
        baked = pad_to_target(Image.open(src))
        out = WORK / f"{SCENE_ID}_cabello_{n}.webp"
        save_webp(baked, out)
        hair_outputs.append((n, out))
        print(f"      -> {out.name} ({out.stat().st_size:,} bytes)")

    # ---- 4. Upload everything + build spec ---------------------------
    print("[4/4] Uploading to Supabase...")

    def upload_img(path: Path):
        body = path.read_bytes()
        supabase_put(IMG_BUCKET, path.name, body, "image/webp", SK)
        return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{path.name}"

    url_fondo    = upload_img(out_fondo)
    url_morrigan = upload_img(out_morrigan)
    url_hair = {}
    for n, path in hair_outputs:
        url_hair[n] = upload_img(path)
    print(f"      uploaded {2 + len(HAIR_FRAMES)} bitmaps")

    # Build cycles spec: frame N visible from (i * step) to ((i+1) * step)
    step = HAIR_CYCLE_DURATION_S / len(HAIR_FRAMES)
    cycle_frames = [
        {"layer_key": f"cabello_{n}",
         "from_s": round(i * step, 4),
         "to_s":   round((i + 1) * step, 4)}
        for i, n in enumerate(HAIR_FRAMES)
    ]

    # Hair layers: first is initial_alpha=1.0 (visible at t=0), rest=0.0
    # (hidden until their window). The cycle then overrides every frame.
    hair_layers = []
    for i, n in enumerate(HAIR_FRAMES):
        hair_layers.append({
            "key": f"cabello_{n}",
            "url": url_hair[n],
            "z": 2,
            "scale": 1.0,
            "parallax_factor": 0.55,
            "scroll_factor": 0.55,
            "offset_x_px": 0,
            "offset_y_px": 0,
            "initial_alpha": 1.0 if i == 0 else 0.0,
            "revision": 1,
        })

    spec = {
        "schema_version": 1,
        "id": SCENE_ID,
        "type": "canvas_scene",
        "title": {"es": "Morrigan · Darkstalkers", "en": "Morrigan · Darkstalkers"},
        "tags": ["anime", "videojuegos", "darkstalkers", "gothic", "morrigan"],
        "category": "videojuegos",
        "featured": True,
        "background": "#0a0418",
        "image_layers": [
            {
                "key": "fondo",
                "url": url_fondo,
                "z": 0,
                "scale": 1.0,
                "parallax_factor": 0.25,
                "scroll_factor": 0.25,
                "offset_x_px": 0,
                "offset_y_px": 0,
                "revision": 1,
            },
            {
                "key": "morrigan",
                "url": url_morrigan,
                "z": 1,
                "scale": 1.0,
                "parallax_factor": 0.55,
                "scroll_factor": 0.55,
                "offset_x_px": 0,
                "offset_y_px": 0,
                "revision": 1,
            },
        ] + hair_layers,
        "cycles": [
            {
                "name": "cabello_swing",
                "duration_s": HAIR_CYCLE_DURATION_S,
                "frames": cycle_frames,
            }
        ],
        "sprites": [],
        "particles": [],
        "events": [],
    }

    spec_body = json.dumps(spec, indent=2).encode("utf-8")
    supabase_put(SCENE_BUCKET, f"{SCENE_ID}.json", spec_body, "application/json", SK)
    print(f"      uploaded spec ({len(spec_body)} bytes)")

    # ---- 5. Preview for the wallpaper grid ----------------------------
    # Use the static composite (Eduardo already made it) — small + cheap.
    print("[5/5] Generating + uploading preview...")
    estatico = Image.open(SRC / "morrigan_wallpaper_estatico.png").convert("RGB")
    preview = estatico.resize((540, 1170), Image.LANCZOS)  # half target
    pv = WORK / f"{SCENE_ID}_preview.webp"
    preview.save(pv, "WEBP", quality=80, method=6)
    supabase_put(IMG_BUCKET, f"{SCENE_ID}_preview.webp", pv.read_bytes(), "image/webp", SK)
    print(f"      uploaded preview ({pv.stat().st_size:,} bytes)")

    print()
    print("DONE — Morrigan Darkstalkers shipped to Supabase OK")
    print(f"      scene id: {SCENE_ID}")
    print(f"      open in sprite editor: http://127.0.0.1:5758/sprite-editor.html")
    print()


if __name__ == "__main__":
    main()
