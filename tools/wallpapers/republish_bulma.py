"""One-off: re-publish all 4 Bulma assets after CapCut enhancement.

Mappings (confirmed with user 2026-05-31):
  - bulma_sexy_00_wallpaperestatico.png → bulma_portrait        (static)
  - bulma_sexy_00_panoramico_00.png     → bulma_bedroom_pano    (panoramic, holographic)
  - bulma_sexy_00_panoramico_01.png     → bulma_vanity_pano     (panoramic, rose gold)
  - bulma_sexy_00_video.mp4             → bulma_live            (live video)

Pipeline per asset:
  1. PNG → WebP (q=92) for main image OR re-encode MP4 to <2MB
  2. Generate preview at appropriate size (<50 KB each)
  3. Upload main + preview to Supabase storage (overwrites existing keys)
  4. Update DB row (wallpapers table) or live_wallpaper_catalog.json with new
     dimensions / sizes
  5. FCM broadcast catalog_invalidate so clients refetch
"""

import os
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
import json
import shutil
import subprocess
import tempfile
import hashlib
from pathlib import Path

import requests
from PIL import Image

# Reuse the existing publisher's secrets so this script doesn't duplicate the
# service-role JWT. Single source of truth: tools/pixora_publish.py. When the
# project eventually migrates that file to env-var loading (see TODO below),
# this script picks it up automatically.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from pixora_publish import SUPABASE_URL, SERVICE_KEY, HEADERS as HEAD  # noqa: E402

# TODO(security): centralize secrets — pixora_publish.py and this script both
# read a hardcoded service_role JWT. Migration plan: read from
# KEYS_LOCAL.md or os.environ['SUPABASE_SERVICE_KEY'] in pixora_publish.py;
# this file inherits the fix via the import above. Tracked for a future
# security-hardening pass; not blocking this content-republish work.

SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo")
TMP = Path(tempfile.mkdtemp(prefix="bulma_republish_"))
print(f"Temp dir: {TMP}\n")


def upload(bucket: str, key: str, body: bytes, content_type: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{key}"
    h = {**HEAD, "Content-Type": content_type, "x-upsert": "true"}
    r = requests.put(url, headers=h, data=body, timeout=180)
    ok = r.status_code in (200, 201)
    print(f"  upload {bucket}/{key}  [{len(body)//1024} KB]  {'OK' if ok else f'FAIL {r.status_code} {r.text[:100]}'}")
    return ok


def png_to_webp(src: Path, dst: Path, quality: int = 92, max_w: int = None) -> tuple[int, int]:
    img = Image.open(src).convert("RGB")
    if max_w and img.size[0] > max_w:
        new_h = int(img.size[1] * max_w / img.size[0])
        img = img.resize((max_w, new_h), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    return img.size


def make_preview_image(src: Path, dst: Path, max_w: int, quality: int = 80) -> int:
    img = Image.open(src).convert("RGB")
    new_h = int(img.size[1] * max_w / img.size[0])
    img = img.resize((max_w, new_h), Image.LANCZOS)
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.stat().st_size


def reencode_video(src: Path, dst: Path, max_w: int = 720, target_kbps: int = 1100):
    # Two-pass for tighter size control. Output: H.264 baseline, no audio, faststart.
    log_prefix = TMP / "ffpass"
    common = [
        "ffmpeg", "-y", "-i", str(src),
        "-vf", f"scale={max_w}:-2",
        "-c:v", "libx264", "-profile:v", "baseline", "-pix_fmt", "yuv420p",
        "-an", "-movflags", "+faststart",
    ]
    # Pass 1
    subprocess.run(common + [
        "-b:v", f"{target_kbps}k", "-pass", "1", "-passlogfile", str(log_prefix),
        "-f", "mp4", "nul" if os.name == "nt" else "/dev/null",
    ], check=True, capture_output=True)
    # Pass 2
    subprocess.run(common + [
        "-b:v", f"{target_kbps}k", "-pass", "2", "-passlogfile", str(log_prefix),
        str(dst),
    ], check=True, capture_output=True)


def make_video_preview(src: Path, dst: Path, size: int = 720, quality: int = 75):
    # Extract frame at ~2s, square crop, encode as WebP
    frame = TMP / "frame.png"
    subprocess.run([
        "ffmpeg", "-y", "-ss", "2", "-i", str(src), "-vframes", "1",
        "-vf", f"crop='min(iw\\,ih)':'min(iw\\,ih)',scale={size}:{size}",
        str(frame),
    ], check=True, capture_output=True)
    img = Image.open(frame).convert("RGB")
    img.save(dst, "WEBP", quality=quality, method=6)
    return dst.stat().st_size


def patch_wallpaper_row(wallpaper_id: str, image_size: int, w: int, h: int, preview_size: int):
    url = f"{SUPABASE_URL}/rest/v1/wallpapers?id=eq.{wallpaper_id}"
    h_ = {**HEAD, "Content-Type": "application/json", "Prefer": "return=minimal"}
    body = {
        "image_size": image_size,
        "preview_size": preview_size,
        "media_width": w,
        "media_height": h,
        "updated_at": "now()",
    }
    r = requests.patch(url, headers=h_, json=body, timeout=20)
    ok = r.status_code in (200, 204)
    print(f"  DB patch {wallpaper_id}: {'OK' if ok else f'FAIL {r.status_code} {r.text[:100]}'}")
    return ok


def update_live_catalog(bulma_video_size: int, bulma_preview_size: int):
    """Fetch live_wallpaper_catalog.json, update bulma_live entry, re-upload."""
    url = f"{SUPABASE_URL}/storage/v1/object/public/wallpaper-videos/live_wallpaper_catalog.json"
    r = requests.get(url, timeout=15)
    if r.status_code != 200:
        print(f"  catalog fetch FAIL: {r.status_code}")
        return False
    cat = r.json()
    updated = False
    for w in cat.get("wallpapers", []):
        if w.get("id") == "bulma_live":
            w["videoSize"] = bulma_video_size
            w["previewSize"] = bulma_preview_size
            updated = True
            print(f"  live_catalog: bulma_live entry updated (videoSize={bulma_video_size}, previewSize={bulma_preview_size})")
            break
    if not updated:
        print("  WARN: bulma_live not found in live_wallpaper_catalog.json")
        return False
    cat["version"] = int(cat.get("version", 0)) + 1
    cat["lastUpdated"] = "now"
    body = json.dumps(cat, ensure_ascii=False, indent=2).encode("utf-8")
    return upload("wallpaper-videos", "live_wallpaper_catalog.json", body, "application/json")


def fcm_broadcast_invalidate():
    """Reuse existing FCM helper if present."""
    helper = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_fcm_push.py")
    if not helper.is_file():
        print("  FCM helper not found — skipping broadcast")
        return
    try:
        r = subprocess.run([sys.executable, str(helper), "catalog_invalidate"],
                           capture_output=True, text=True, timeout=30)
        print(f"  FCM: {r.returncode}  {r.stdout.strip()[:200]}{r.stderr.strip()[:200]}")
    except Exception as e:
        print(f"  FCM error: {e}")


# ── Mapping ──────────────────────────────────────────────────────────
ASSETS = [
    {
        "kind": "image",
        "local": SRC_DIR / "bulma_sexy_00_wallpaperestatico.png",
        "id": "bulma_portrait",
        "main_key": "bulma_portrait.webp",
        "preview_key": "bulma_portrait_preview.webp",
        "bucket": "wallpaper-images",
        "preview_w": 540,
        "main_max_w": 1080,  # keep portrait at 1080 wide
    },
    {
        "kind": "image",
        "local": SRC_DIR / "bulma_sexy_00_panoramico_00.png",
        "id": "bulma_bedroom_pano",
        "main_key": "bulma_bedroom_pano.webp",
        "preview_key": "bulma_bedroom_pano_preview.webp",
        "bucket": "wallpaper-images",
        "preview_w": 1024,
        "main_max_w": 4128,
    },
    {
        "kind": "image",
        "local": SRC_DIR / "bulma_sexy_00_panoramico_01.png",
        "id": "bulma_vanity_pano",
        "main_key": "bulma_vanity_pano.webp",
        "preview_key": "bulma_vanity_pano_preview.webp",
        "bucket": "wallpaper-images",
        "preview_w": 1024,
        "main_max_w": 4128,
    },
    {
        "kind": "video",
        "local": SRC_DIR / "bulma_sexy_00_video.mp4",
        "id": "bulma_live",
        "main_key": "videos/bulma_live.mp4",
        "preview_key": "previews/bulma_live_preview.webp",
        "bucket": "wallpaper-videos",
        "target_kbps": 1100,
        "max_w": 720,
    },
]


print("═" * 70)
print(" BULMA REPUBLISH PIPELINE")
print("═" * 70)

results = {}
for a in ASSETS:
    print(f"\n── {a['id']}  ({a['kind']})  ──")
    if not a["local"].is_file():
        print(f"  MISSING: {a['local']}")
        continue

    if a["kind"] == "image":
        # Convert main
        main_webp = TMP / f"{a['id']}_main.webp"
        w, h = png_to_webp(a["local"], main_webp, quality=92, max_w=a["main_max_w"])
        main_bytes = main_webp.read_bytes()
        print(f"  main: {w}×{h}  {len(main_bytes)//1024} KB (webp q=92)")

        # Preview
        preview_webp = TMP / f"{a['id']}_preview.webp"
        psize = make_preview_image(a["local"], preview_webp, max_w=a["preview_w"], quality=80)
        preview_bytes = preview_webp.read_bytes()
        print(f"  preview: {a['preview_w']} wide  {len(preview_bytes)//1024} KB")

        # Upload
        upload(a["bucket"], a["main_key"], main_bytes, "image/webp")
        upload(a["bucket"], a["preview_key"], preview_bytes, "image/webp")

        # Patch DB
        patch_wallpaper_row(a["id"], len(main_bytes), w, h, len(preview_bytes))
        results[a["id"]] = {"main": len(main_bytes), "preview": len(preview_bytes), "w": w, "h": h}

    elif a["kind"] == "video":
        # Re-encode
        out_mp4 = TMP / f"{a['id']}.mp4"
        print(f"  re-encoding to ≤2 MB target (max_w={a['max_w']}, {a['target_kbps']}k)...")
        reencode_video(a["local"], out_mp4, max_w=a["max_w"], target_kbps=a["target_kbps"])
        main_bytes = out_mp4.read_bytes()
        print(f"  main: {len(main_bytes)//1024} KB")

        # Preview from video
        preview_webp = TMP / f"{a['id']}_preview.webp"
        psize = make_video_preview(a["local"], preview_webp, size=720, quality=75)
        preview_bytes = preview_webp.read_bytes()
        print(f"  preview: 720×720  {len(preview_bytes)//1024} KB")

        # Upload
        upload(a["bucket"], a["main_key"], main_bytes, "video/mp4")
        upload(a["bucket"], a["preview_key"], preview_bytes, "image/webp")

        # live_wallpaper_catalog.json update happens after
        results[a["id"]] = {"main": len(main_bytes), "preview": len(preview_bytes)}


# ── Update live catalog JSON (for bulma_live entry) ─────────────────
print(f"\n── live_wallpaper_catalog.json update ──")
if "bulma_live" in results:
    update_live_catalog(
        bulma_video_size=results["bulma_live"]["main"],
        bulma_preview_size=results["bulma_live"]["preview"],
    )

# ── FCM broadcast ────────────────────────────────────────────────────
print(f"\n── FCM catalog_invalidate broadcast ──")
fcm_broadcast_invalidate()

print(f"\n═══ DONE ═══")
print(f"Temp files left at: {TMP}  (delete manually if you want)")
