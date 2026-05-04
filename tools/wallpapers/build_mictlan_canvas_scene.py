"""
Build all assets needed for Mictlantecuhtli as a canvas_scene wallpaper:

  1. Background: clean panoramic without the character
     -> wallpaper-images/mictlan_background.webp

  2. Character sprite frames: 61 PNGs with alpha, packaged as ZIP
     -> wallpaper-sprites/mictlantecuhtli/god.zip
     -> wallpaper-sprites/manifest.json (patched with new entry)

  3. Scene spec JSON
     -> wallpaper-videos/scenes/mictlantecuhtli.json

After this runs, the catalog entry just needs `type: canvas_scene` and the
spec URL — no Flutter rebuild needed (one-time native change wires the
canvas_scene flow to read manifest_key from any spec).
"""
from __future__ import annotations
import io, json, os, re, sys, urllib.request, zipfile
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
PROJECT = "vzuwvsmlyigjtsearxym"
SVC = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
                KEYS.read_text(encoding="utf-8")).group(1)

SRC = Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/mitologia/mesoamericana")
GIF = SRC / " MICTLANTECUHTLI_gif.gif"
BG  = SRC / "imagen_fondo_ MICTLANTECUHTLI.png"

TMP = Path(r"C:/Users/lalo/AppData/Local/Temp/mictlan_scene")
TMP.mkdir(parents=True, exist_ok=True)


def supabase_put(bucket: str, key: str, body: bytes, ctype: str):
    url = f"https://{PROJECT}.supabase.co/storage/v1/object/{bucket}/{key}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("Content-Type", ctype)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.status


def supabase_get(bucket: str, key: str) -> bytes | None:
    url = f"https://{PROJECT}.supabase.co/storage/v1/object/public/{bucket}/{key}"
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def clean_green_halo(rgba: Image.Image) -> Image.Image:
    px = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = px[x, y]
            if a == 0: continue
            if g > 180 and r < 110 and b < 110:
                px[x, y] = (0, 0, 0, 0)
            elif g > r + 25 and g > b + 25:
                neutral = (r + b) // 2
                fade = max(0, 255 - (g - neutral) * 3)
                px[x, y] = (r, neutral, b, min(a, fade))
    return rgba


def main():
    # ── 1. BACKGROUND — clean panoramic, no character ─────────────────────
    print("1) Building background...")
    bg = Image.open(BG).convert("RGB")
    # Encode as WebP, quality 82 → ~150 KB for 2700x1080
    bg_out = TMP / "mictlan_background.webp"
    bg.save(bg_out, "WEBP", quality=82, method=6)
    print(f"   Background: {bg_out.stat().st_size / 1024:.0f} KB")
    supabase_put("wallpaper-images", "mictlan_background.webp",
                 bg_out.read_bytes(), "image/webp")
    print(f"   Uploaded to wallpaper-images/mictlan_background.webp")

    # ── 2. CHARACTER SPRITE FRAMES (61 PNGs with alpha) ────────────────────
    print("\n2) Building character sprite frames...")
    gif = Image.open(GIF)
    n = gif.n_frames
    gif.seek(0)
    bbox = gif.convert("RGBA").getbbox()  # 668,29,952,618 = 284x589
    print(f"   GIF: {n} frames, char bbox {bbox}")

    # Each sprite is the cropped character at native size (no resize — engine
    # scales at draw time using the spec's `scale` param). PNG with alpha.
    sprites_dir = TMP / "sprites"
    sprites_dir.mkdir(exist_ok=True)
    for i in range(n):
        gif.seek(i)
        char = gif.convert("RGBA").crop(bbox)
        char = clean_green_halo(char)
        char.save(sprites_dir / f"frame_{i+1:03d}.png", "PNG", optimize=True)

    # Package the 61 PNGs into a ZIP for the SpriteDownloadService
    zip_path = TMP / "god.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for f in sorted(sprites_dir.glob("frame_*.png")):
            z.write(f, arcname=f.name)
    print(f"   Sprite ZIP: {zip_path.stat().st_size / 1024:.0f} KB ({n} frames)")
    supabase_put("wallpaper-sprites", "mictlantecuhtli/god.zip",
                 zip_path.read_bytes(), "application/zip")
    print(f"   Uploaded to wallpaper-sprites/mictlantecuhtli/god.zip")

    # ── 3. SPRITE MANIFEST PATCH ───────────────────────────────────────────
    print("\n3) Patching wallpaper-sprites/manifest.json...")
    raw = supabase_get("wallpaper-sprites", "manifest.json") or b"{}"
    manifest = json.loads(raw or b"{}")
    manifest["mictlantecuhtli/god"] = {
        "zip": "mictlantecuhtli/god.zip",
        "frames": n,
    }
    body = json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8")
    supabase_put("wallpaper-sprites", "manifest.json", body, "application/json")
    print(f"   Patched: {len(manifest)} sprite folders total")

    # ── 4. SCENE SPEC ──────────────────────────────────────────────────────
    print("\n4) Building scene spec...")
    spec = {
        "schema_version": 1,
        "id": "mictlantecuhtli",
        "type": "canvas_scene",
        "title": {"en": "Mictlantecuhtli", "es": "Mictlantecuhtli · Señor del Mictlán"},
        "tags": ["mythology", "aztec", "mexica", "underworld", "death", "live"],
        "category": "culture",
        "featured": True,
        "background": {
            "url": f"https://{PROJECT}.supabase.co/storage/v1/object/public/wallpaper-images/mictlan_background.webp",
            "preview_url": f"https://{PROJECT}.supabase.co/storage/v1/object/public/wallpaper-videos/previews/mictlantecuhtli_preview_v2.webp",
            "scroll": True,  # background pans horizontally with home swipe
        },
        "sprites": [
            {
                "name": "god",
                "manifest_key": "mictlantecuhtli/god",
                "behavior": "static",
                "frame_skip": 3,  # advance 1 frame every 3 ticks → ~10 fps loop
                "params": {
                    "x": 0.5,           # centered horizontally
                    "y": 0.86,          # near bottom (feet on the spectral water)
                    "scale": 0.0011,    # ~25% of screen height (small for depth)
                    "alpha": 255
                }
            }
        ],
        "particles": [
            {
                "type": "wisp",
                "params": {
                    "color": "#FFB8DCFF",   # white with cyan-blue tint = soul
                    "radius": 0.022,
                    "wobble_amplitude": 12,
                    "anchors": [
                        [0.18, 0.62], [0.32, 0.71], [0.48, 0.66],
                        [0.62, 0.74], [0.78, 0.65], [0.86, 0.78],
                        [0.12, 0.82], [0.28, 0.88], [0.55, 0.88],
                        [0.72, 0.83], [0.42, 0.55], [0.65, 0.58]
                    ]
                }
            },
            {
                "type": "ember",
                "params": {
                    "count": 18,
                    "color": "#FFE0F4FF",   # icy white spectral motes
                    "size_min_px": 1.5,
                    "size_max_px": 3.5,
                    "rise_speed_min": 0.2,
                    "rise_speed_max": 0.6,
                    "drift_amp_px": 8
                }
            }
        ],
        "events": [
            {
                "kind": "flash_overlay",
                "interval_s": 11,
                "duration_s": 0.6,
                "params": {
                    "color": "#3A8AC8",    # cool blue pulse
                    "peak_alpha": 36       # subtle — like the Mictlán "breathing"
                }
            }
        ]
    }
    spec_bytes = json.dumps(spec, ensure_ascii=False, indent=2).encode("utf-8")
    spec_local = TMP / "mictlantecuhtli.json"
    spec_local.write_bytes(spec_bytes)
    # Upload to wallpaper-videos bucket so the catalog can reference it
    supabase_put("wallpaper-videos", "scenes/mictlantecuhtli.json",
                 spec_bytes, "application/json")
    # Also keep a copy in docs/scenes for git history
    docs_copy = Path(r"D:/Orbix/Pixora-IA/docs/scenes/mictlantecuhtli.json")
    docs_copy.write_bytes(spec_bytes)
    print(f"   Spec: {len(spec_bytes)} bytes")
    print(f"   Uploaded to wallpaper-videos/scenes/mictlantecuhtli.json")
    print(f"   Local copy at {docs_copy}")
    print()
    print("ALL UPLOADED. Next:")
    print("  - Modify SpriteDownloadService to dynamically extract manifest_keys from spec")
    print("  - Patch the catalog: mictlantecuhtli.type = canvas_scene")
    print("  - Build + install APK")


if __name__ == "__main__":
    main()
