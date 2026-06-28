"""Re-publish Spiderman after GIMP hero fix — bust layer cache with hero_v4."""
from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/spiderman_enel_aire")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_spiderman_enel_aire")

SRC_BG = SRC / "fondo_spiderman.png"
SRC_HERO = SRC / "spiderman_soloelpersonage.png"

TARGET = (1080, 2340)
SCENE_ID = "spiderman_enel_aire"
IMG_BUCKET = "wallpaper-images"
SCENES_BUCKET = "wallpaper-scenes"

R_BG = f"{SCENE_ID}_bg_v2.webp"
R_HERO = f"{SCENE_ID}_hero_v4.webp"
R_FLAT = f"{SCENE_ID}.webp"
R_PREVIEW = f"{SCENE_ID}_preview.webp"
R_SPEC = f"{SCENE_ID}.json"


def load_service_key() -> str:
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_service_key()


def cover_fit(img, target=TARGET, transparent=False):
    from PIL import Image

    tw, th = target
    src = img.convert("RGBA")
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    nw, nh = int(round(sw * scale)), int(round(sh * scale))
    resized = src.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    cropped = resized.crop((left, top, left + tw, top + th))
    if not transparent:
        out = Image.new("RGB", target, (0, 0, 0))
        out.paste(cropped, mask=cropped.split()[3])
        return out
    return cropped


def put(bucket: str, remote: str, body: bytes, ct: str) -> None:
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body,
        method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def get_json(bucket: str, remote: str) -> dict:
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def main() -> None:
    from PIL import Image

    WORK.mkdir(parents=True, exist_ok=True)
    print(f"Source hero: {SRC_HERO.name} ({SRC_HERO.stat().st_size:,} B)")

    bg_rgba = cover_fit(Image.open(SRC_BG), transparent=True)
    hero_rgba = cover_fit(Image.open(SRC_HERO), transparent=True)

    out_hero = WORK / R_HERO
    hero_rgba.save(out_hero, "WEBP", lossless=True)
    a = hero_rgba.split()[3]
    print(f"  hero alpha {a.getextrema()}")

    # Flat = bg + hero composite (aligned with live layers)
    flat_rgba = Image.alpha_composite(bg_rgba, hero_rgba)
    flat_rgb = Image.new("RGB", TARGET, (0, 0, 0))
    flat_rgb.paste(flat_rgba, mask=flat_rgba.split()[3])
    out_flat = WORK / R_FLAT
    out_prev = WORK / R_PREVIEW
    flat_rgb.save(out_flat, "WEBP", quality=88, method=6)
    prev = flat_rgb.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(out_prev, "WEBP", quality=85, method=6)

    put(IMG_BUCKET, R_HERO, out_hero.read_bytes(), "image/webp")
    put(IMG_BUCKET, R_FLAT, out_flat.read_bytes(), "image/webp")
    put(IMG_BUCKET, R_PREVIEW, out_prev.read_bytes(), "image/webp")

    spec = get_json(SCENES_BUCKET, R_SPEC)
    url_hero = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_HERO}"
    url_flat = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_FLAT}"
    url_prev = f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{R_PREVIEW}"
    spec["background"]["url"] = url_flat
    spec["background"]["preview_url"] = url_prev
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from scene_layer_utils import bump_layer_revisions, put_scene_spec

    for layer in spec.get("image_layers", []):
        if layer.get("key") == "spiderman":
            layer["url"] = url_hero
    bumped = bump_layer_revisions(spec, ["spiderman"])
    put_scene_spec(SCENE_ID, spec, SK)
    print(f"  spec saved (hero -> {R_HERO}, revision bump {bumped})")

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect

    conn = connect()
    cur = conn.cursor()
    cur.execute(
        """
        UPDATE wallpapers
        SET image_path=%s, preview_path=%s,
            image_size=%s, preview_size=%s, updated_at=now()
        WHERE id=%s
        """,
        (R_FLAT, R_PREVIEW, out_flat.stat().st_size, out_prev.stat().st_size, SCENE_ID),
    )
    conn.commit()
    cur.close()
    conn.close()

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate

    print(f"  fcm -> {send_catalog_invalidate('wallpapers')}")
    print("OK — reaplica el wallpaper o espera FCM + reload")


if __name__ == "__main__":
    main()