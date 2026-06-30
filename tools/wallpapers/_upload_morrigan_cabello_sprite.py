"""Convert Morrigan's 6 hair frames into a single sprite (zip) — same pattern
as ryu_hadouken_orb.

After this runs:
- morrigan_darkstalkers.json loses the 6 cabello_* image_layers and the
  cabello_swing cycle
- It gains 1 sprite entry `cabello` referencing manifest_key `morrigan_cabello`
- The sprite zip is uploaded to wallpaper-sprites/morrigan_cabello.zip
- The shared wallpaper-sprites/manifest.json gets the new entry

Result: in the sprite editor Morrigan has 3 objects total (fondo, morrigan,
cabello) instead of 8. The cabello sprite animates by itself.
"""
import io
import json
import re
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image

SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/darkstalkers")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_morrigan_cabello_sprite")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
IMG_BUCKET   = "wallpaper-images"
SCN_BUCKET   = "wallpaper-scenes"
SPR_BUCKET   = "wallpaper-sprites"
MANIFEST_KEY = "manifest.json"

SCENE_ID         = "morrigan_darkstalkers"
SPRITE_NAME      = "cabello"
SPRITE_MANIFEST_KEY = "morrigan_cabello"  # entry name in wallpaper-sprites/manifest.json
SPRITE_ZIP_NAME  = "morrigan_cabello.zip"

# Source frames (05 missing in source — loop runs 00->01->02->03->04->06)
HAIR_FRAMES = ["00", "01", "02", "03", "04", "06"]

# Crop padding around the alpha bbox (px). Keeps a halo so anti-aliased
# edges don't cut sharply.
CROP_PAD = 6


def supabase_get_json(bucket: str, key: str) -> dict:
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{key}?t=999"
    return json.loads(urllib.request.urlopen(url).read())


def supabase_put(bucket: str, key: str, body: bytes, ctype: str, sk: str):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{key}",
        data=body, method="PUT",
        headers={"Authorization": f"Bearer {sk}", "apikey": sk,
                 "Content-Type": ctype, "x-upsert": "true",
                 "Cache-Control": "no-cache, max-age=0"}
    )
    return urllib.request.urlopen(req)


def main():
    SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]

    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)

    # ---- 1. Find shared bbox across all frames ------------------------
    # All frames must share crop dimensions so the sprite animation has
    # consistent geometry. Take the union of all subject bboxes.
    print("[1/5] Computing shared bbox across all hair frames...")
    import numpy as np
    xs_min, xs_max = float("inf"), 0
    ys_min, ys_max = float("inf"), 0
    for n in HAIR_FRAMES:
        src = SRC / f"cabello_frame_{n}.png"
        im = Image.open(src).convert("RGBA")
        a = np.array(im)[:, :, 3]
        ys, xs = np.where(a > 30)
        if len(xs) == 0:
            continue
        xs_min = min(xs_min, xs.min())
        xs_max = max(xs_max, xs.max())
        ys_min = min(ys_min, ys.min())
        ys_max = max(ys_max, ys.max())
    src_w, src_h = im.size  # all source frames are 1080x1920
    bbox_l = max(0, int(xs_min) - CROP_PAD)
    bbox_t = max(0, int(ys_min) - CROP_PAD)
    bbox_r = min(src_w, int(xs_max) + CROP_PAD + 1)
    bbox_b = min(src_h, int(ys_max) + CROP_PAD + 1)
    crop_w = bbox_r - bbox_l
    crop_h = bbox_b - bbox_t
    print(f"      bbox: x=[{bbox_l}..{bbox_r}] y=[{bbox_t}..{bbox_b}] -> {crop_w}x{crop_h}")

    # Compute the subject's center IN THE ORIGINAL 1080x1920 frame, normalized.
    # The sprite renderer positions the sprite by its anchor (default 0.5,0.5),
    # so we need to point it to where the hair *was* in the original composition.
    # Hair center in original 1080x1920:
    cx_src = (bbox_l + bbox_r) / 2.0
    cy_src = (bbox_t + bbox_b) / 2.0
    # Now translate to TARGET 1080x2340 (source was vertically centered in it
    # in the bake step → original y range [210..2130] in target). So:
    cy_target = cy_src + (2340 - 1920) // 2  # = cy_src + 210
    norm_x = cx_src / 1080.0
    norm_y = cy_target / 2340.0
    print(f"      sprite anchor in TARGET 1080x2340: x={norm_x:.4f} y={norm_y:.4f}")

    # Sprite scale so the rendered hair matches the original size on TARGET.
    # Formula (scene_coords.js): rw = decW * scale * surfaceW
    # We want rw = crop_w (the original size in pixels) on a surface where
    # surfaceW = 1080 (TARGET width). Sprite uses high_res so decW = crop_w
    # (no sampleSize division). Thus:
    #   crop_w = crop_w * scale * 1080  ->  scale = 1/1080 = 0.000926
    sprite_scale = round(1.0 / 1080.0, 6)
    print(f"      sprite scale = {sprite_scale} (matches original px size)")

    # ---- 2. Crop each frame to that bbox ------------------------------
    print(f"[2/5] Cropping {len(HAIR_FRAMES)} frames to {crop_w}x{crop_h}...")
    cropped_frames = []
    for n in HAIR_FRAMES:
        im = Image.open(SRC / f"cabello_frame_{n}.png").convert("RGBA")
        cropped = im.crop((bbox_l, bbox_t, bbox_r, bbox_b))
        cropped_frames.append(cropped)
        # Save individual file for debugging
        cropped.save(WORK / f"frame_{HAIR_FRAMES.index(n):03d}.png", "PNG", optimize=True)

    # ---- 3. Build ZIP -------------------------------------------------
    print("[3/5] Building sprite ZIP...")
    zip_buf = io.BytesIO()
    raw_total = 0
    with zipfile.ZipFile(zip_buf, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for i, cropped in enumerate(cropped_frames):
            img_buf = io.BytesIO()
            cropped.save(img_buf, "PNG", optimize=True)
            data = img_buf.getvalue()
            zf.writestr(f"frame_{i:03d}.png", data)
            raw_total += len(data)
    zip_bytes = zip_buf.getvalue()
    (WORK / SPRITE_ZIP_NAME).write_bytes(zip_bytes)
    print(f"      {SPRITE_ZIP_NAME}: {len(HAIR_FRAMES)} frames, "
          f"zip={len(zip_bytes):,} B (raw={raw_total:,} B)")

    # ---- 4. Upload ZIP + update sprite manifest -----------------------
    print("[4/5] Uploading sprite ZIP + manifest...")
    supabase_put(SPR_BUCKET, SPRITE_ZIP_NAME, zip_bytes, "application/zip", SK)
    manifest = supabase_get_json(SPR_BUCKET, MANIFEST_KEY)
    manifest[SPRITE_MANIFEST_KEY] = {
        "zip": SPRITE_ZIP_NAME,
        "frames": len(HAIR_FRAMES),
        "size": len(zip_bytes),
    }
    supabase_put(SPR_BUCKET, MANIFEST_KEY,
                 json.dumps(manifest, indent=2).encode("utf-8"),
                 "application/json", SK)
    print(f"      manifest entry: {SPRITE_MANIFEST_KEY}")

    # ---- 5. Update scene spec: drop cabello_* layers + cycle, add sprite
    print("[5/5] Updating scene spec...")
    spec = supabase_get_json(SCN_BUCKET, f"{SCENE_ID}.json")

    # Drop all cabello_* image_layers (keep fondo, morrigan)
    spec["image_layers"] = [l for l in spec["image_layers"]
                            if not l["key"].startswith("cabello_")]
    # Drop the cycle that was multiplexing them
    spec["cycles"] = [c for c in spec.get("cycles", [])
                      if c.get("name") != "cabello_swing"]

    # Add the cabello sprite. behavior="static" + frame_skip>0 cycles forever.
    # frame_skip=4 means a new frame every 4 render ticks (~67ms at 60fps,
    # i.e. ~15fps animation — close to the 6fps look but smoother).
    sprite_entry = {
        "name": SPRITE_NAME,
        "manifest_key": SPRITE_MANIFEST_KEY,
        "behavior": "static",
        "frame_skip": 6,  # ~10fps at 60Hz, gentle hair swing
        "params": {
            "x": norm_x,
            "y": norm_y,
            "scale": sprite_scale,
            "alpha": 255,
            "parallax_factor": 0.55,
            "high_res": True,
        }
    }
    spec.setdefault("sprites", []).append(sprite_entry)

    body = json.dumps(spec, indent=2).encode("utf-8")
    supabase_put(SCN_BUCKET, f"{SCENE_ID}.json", body, "application/json", SK)
    print(f"      spec updated: image_layers={len(spec['image_layers'])} "
          f"cycles={len(spec.get('cycles', []))} sprites={len(spec.get('sprites', []))}")

    print()
    print("DONE - morrigan cabello converted to a sprite OK")
    print(f"     sprite manifest_key: {SPRITE_MANIFEST_KEY}")
    print(f"     position on TARGET (normalized): x={norm_x:.3f} y={norm_y:.3f}")
    print(f"     scale: {sprite_scale}")
    print()
    print("Refresca el sprite editor para ver el cambio.")
    print("Si la posicion del cabello no calza con la cabeza de Morrigan,")
    print("arrastra el sprite en el editor (no hace falta re-correr este script).")


if __name__ == "__main__":
    main()
