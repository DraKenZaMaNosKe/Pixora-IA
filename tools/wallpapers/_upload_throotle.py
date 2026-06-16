"""
Pixora content publisher — Throotle Underwater (Pokemon turtle, anime).

Source: C:/Users/lalo/Desktop/wallPapers_repo/nuevos/throotle/
  - thotle_underwater_.mp4 (9.4 MB con audio, 1080x1920, 6s 30fps)
  - throottle_underwater_completa.png (4.7 MB, 1080x2160 RGBA)

Outputs:
  1. Static  → throotle_underwater     → wallpaper-images   (WebP)
  2. Live    → throotle_underwater_auto    → wallpaper-videos  (MP4 autoplay)
  3. Live    → throotle_underwater_explore → wallpaper-videos  (MP4 + 15 frames)

2026-06-16 — Low-RAM optimization vs Snoopy:
  · 15 frames @ 720x1280 (vs 24 frames @ 1080x1920) → ~50% menos memoria
  · Mismo MP4 resolution para autoplay (no afecta footprint del MediaPlayer)
  · Target: 4GB Samsung aguanta 4-5 wallpapers consecutivos sin lmkd-kill

Phase 2 (futuro): parallax canvas scene con fondo + foreground + depth grayscale.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# ───────────────────── config ─────────────────────
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/throotle")
WORK_DIR = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_throotle")

# Source filenames (Eduardo's filename has inconsistent 't's — capture exact names):
#   PNG completa: "throttle_underwater_completa.png"  (double-t throttle)
#   MP4 video:    "thotle_underwater_.mp4"            (single-t thotle, _suffix)
SRC_PNG = SRC_DIR / "throttle_underwater_completa.png"
SRC_MP4 = SRC_DIR / "thotle_underwater_.mp4"

OUT_STATIC_WEBP = WORK_DIR / "throotle_underwater.webp"
OUT_STATIC_PREVIEW = WORK_DIR / "throotle_underwater_static_preview.webp"
OUT_VIDEO_MP4 = WORK_DIR / "throotle_underwater.mp4"
OUT_VIDEO_PREVIEW = WORK_DIR / "throotle_underwater_preview.webp"
OUT_FRAMES_DIR = WORK_DIR / "frames"

STATIC_BUCKET = "wallpaper-images"
LIVE_BUCKET = "wallpaper-videos"

STATIC_IMG_REMOTE = "throotle_underwater.webp"
STATIC_PREV_REMOTE = "throotle_underwater_preview.webp"
LIVE_VIDEO_REMOTE = "videos/throotle_underwater.mp4"
LIVE_PREV_REMOTE = "previews/throotle_underwater_preview.webp"
LIVE_FRAMES_PATH = "frames/throotle_underwater_explore"

CATALOG_REMOTE = "live_wallpaper_catalog.json"

STATIC_ID = "throotle_underwater"
LIVE_AUTO_ID = "throotle_underwater_auto"
LIVE_EXPLORE_ID = "throotle_underwater_explore"

# Pokemon ocean kawaii vibes
TAGS = ["anime", "pokemon", "throotle", "tortuga", "agua",
        "ocean", "underwater", "cute", "azul"]
GLOW = "#5BC7FF"  # cyan ocean

# Low-RAM Explore params (vs Snoopy: 24 frames @ 1080p → 15 frames @ 720p)
EXPLORE_FPS = 2.5  # 6s × 2.5 = 15 frames
EXPLORE_WIDTH = 720
EXPLORE_HEIGHT = 1280


def load_service_key() -> str:
    keys = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", keys)
    if not m:
        raise SystemExit("Service Role Key no encontrado en KEYS_LOCAL.md")
    return m.group(1)


SERVICE_KEY = load_service_key()


def run(cmd, check=True):
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check and r.returncode != 0:
        print(f"    STDERR: {r.stderr[-500:]}")
        raise SystemExit(f"Comando fallo (exit {r.returncode})")
    return r


def storage_put(bucket, remote, local, content_type):
    body = local.read_bytes()
    url = f"{PROJECT}/storage/v1/object/{bucket}/{remote}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", content_type)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote}  -> {r.status} ({len(body):,} bytes)")
    return len(body)


def storage_get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def storage_put_json(bucket, remote, data):
    payload = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    url = f"{PROJECT}/storage/v1/object/{bucket}/{remote}"
    req = urllib.request.Request(url, data=payload, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote}  -> {r.status} (catalog)")


# ───────────────────── FASE 1: procesar local ─────────────────────
def phase1_process_local():
    from PIL import Image

    print("\n[1/5] Procesamiento local (low-RAM optimized)")
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    OUT_FRAMES_DIR.mkdir(parents=True, exist_ok=True)

    info = {}

    # 1a. PNG -> WebP (full quality static)
    print("  · Static PNG -> WebP q90")
    img = Image.open(SRC_PNG).convert("RGBA")
    info["width"] = img.width
    info["height"] = img.height
    img.save(OUT_STATIC_WEBP, "WEBP", quality=90, method=6)
    info["static_webp_size"] = OUT_STATIC_WEBP.stat().st_size
    print(f"    {img.width}x{img.height}, {info['static_webp_size']:,} bytes")

    # 1b. Static preview (small)
    print("  · Static preview 540x1170 WebP")
    prev = img.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_STATIC_PREVIEW, "WEBP", quality=85, method=6)
    info["static_preview_size"] = OUT_STATIC_PREVIEW.stat().st_size
    print(f"    {prev.width}x{prev.height}, {info['static_preview_size']:,} bytes")

    # 1c. MP4 re-encode sin audio, 2 Mbps (same as Snoopy)
    print("  · MP4 -> H.264 baseline sin audio, 2 Mbps")
    if OUT_VIDEO_MP4.exists():
        OUT_VIDEO_MP4.unlink()
    run([
        "ffmpeg", "-y", "-i", str(SRC_MP4),
        "-an",
        "-c:v", "libx264", "-profile:v", "baseline", "-level", "4.0",
        "-b:v", "2000k", "-maxrate", "2500k", "-bufsize", "4000k",
        "-movflags", "+faststart",
        "-pix_fmt", "yuv420p",
        "-loglevel", "error",
        str(OUT_VIDEO_MP4),
    ])
    info["video_size"] = OUT_VIDEO_MP4.stat().st_size
    print(f"    {info['video_size']:,} bytes")

    # 1d. Video preview (small WebP animated)
    print("  · Live preview 480x480 WebP animated (light)")
    if OUT_VIDEO_PREVIEW.exists():
        OUT_VIDEO_PREVIEW.unlink()
    run([
        "ffmpeg", "-y", "-i", str(OUT_VIDEO_MP4),
        "-vf", "scale=480:480:force_original_aspect_ratio=increase,crop=480:480,fps=6",
        "-loop", "0", "-lossless", "0", "-compression_level", "6", "-q:v", "50",
        "-loglevel", "error",
        str(OUT_VIDEO_PREVIEW),
    ])
    info["video_preview_size"] = OUT_VIDEO_PREVIEW.stat().st_size
    print(f"    {info['video_preview_size']:,} bytes")

    # 1e. Extraer frames LOW-RAM (15 @ 720p)
    print(f"  · Extraer frames Explore: {EXPLORE_WIDTH}x{EXPLORE_HEIGHT} @ fps={EXPLORE_FPS}")
    for f in OUT_FRAMES_DIR.glob("frame_*.jpg"):
        f.unlink()
    run([
        "ffmpeg", "-y", "-i", str(OUT_VIDEO_MP4),
        "-vf", f"fps={EXPLORE_FPS},scale={EXPLORE_WIDTH}:{EXPLORE_HEIGHT}",
        "-q:v", "4",
        "-loglevel", "error",
        str(OUT_FRAMES_DIR / "frame_%04d.jpg"),
    ])
    frames = sorted(OUT_FRAMES_DIR.glob("frame_*.jpg"))
    info["frame_count"] = len(frames)
    total = sum(f.stat().st_size for f in frames)
    print(f"    {len(frames)} frames, total {total:,} bytes (vs Snoopy 4.8 MB)")
    return info


def phase2_upload(info):
    print("\n[2/5] Upload Supabase Storage")
    storage_put(STATIC_BUCKET, STATIC_IMG_REMOTE, OUT_STATIC_WEBP, "image/webp")
    storage_put(STATIC_BUCKET, STATIC_PREV_REMOTE, OUT_STATIC_PREVIEW, "image/webp")
    storage_put(LIVE_BUCKET, LIVE_VIDEO_REMOTE, OUT_VIDEO_MP4, "video/mp4")
    storage_put(LIVE_BUCKET, LIVE_PREV_REMOTE, OUT_VIDEO_PREVIEW, "image/webp")
    print(f"  · Uploading {info['frame_count']} frames")
    for f in sorted(OUT_FRAMES_DIR.glob("frame_*.jpg")):
        storage_put(LIVE_BUCKET, f"{LIVE_FRAMES_PATH}/{f.name}", f, "image/jpeg")


def phase3_insert_static(info):
    print("\n[3/5] INSERT Postgres wallpapers (static)")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect

    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    print(f"  next sort_order: {next_sort}")
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'ANIME'::wallpaper_category, %s,
            %s, %s, %s, %s,
            %s, 'NEW'::wallpaper_badge, %s, false, 0,
            true, true, %s, %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            description = EXCLUDED.description,
            tags = EXCLUDED.tags,
            image_path = EXCLUDED.image_path,
            preview_path = EXCLUDED.preview_path,
            image_size = EXCLUDED.image_size,
            preview_size = EXCLUDED.preview_size,
            glow_color = EXCLUDED.glow_color,
            badge = EXCLUDED.badge,
            published = EXCLUDED.published,
            daily_eligible = EXCLUDED.daily_eligible,
            media_width = EXCLUDED.media_width,
            media_height = EXCLUDED.media_height,
            updated_at = now()
        RETURNING id;
    """, (
        STATIC_ID,
        "Throotle Underwater",
        "Throotle Pokemon flotando entre corales bajo el mar — ilustracion kawaii bajo rayos de sol",
        TAGS,
        STATIC_IMG_REMOTE,
        STATIC_PREV_REMOTE,
        info["static_webp_size"],
        info["static_preview_size"],
        GLOW,
        next_sort,
        "Pixora Studio",
        info["width"],
        info["height"],
    ))
    print(f"  upserted: {cur.fetchone()[0]}")
    conn.commit(); cur.close(); conn.close()


def phase4_live_catalog(info):
    print("\n[4/5] UPSERT live_wallpaper_catalog.json (auto + explore)")
    catalog = storage_get_json(LIVE_BUCKET, CATALOG_REMOTE)
    wallpapers = catalog["wallpapers"]
    max_sort = max((w.get("sortOrder", 0) for w in wallpapers), default=0)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    entry_auto = {
        "id": LIVE_AUTO_ID,
        "name": "Throotle Underwater",
        "description": "Throotle bajo el mar entre corales y rayos de sol — video looping",
        "videoFile": LIVE_VIDEO_REMOTE,
        "previewFile": LIVE_PREV_REMOTE,
        "videoSize": info["video_size"],
        "previewSize": info["video_preview_size"],
        "glowColor": GLOW,
        "category": "ANIME",
        "type": "video",
        "badge": "NEW",
        "sortOrder": max_sort + 1,
        "tags": TAGS,
        "downloadCount": 0,
        "createdAt": now_iso,
    }
    entry_explore = {
        "id": LIVE_EXPLORE_ID,
        "name": "Throotle Underwater · Explore",
        "description": "Throotle bajo el mar — toca y desliza para explorar cuadro a cuadro",
        "videoFile": LIVE_VIDEO_REMOTE,
        "previewFile": LIVE_PREV_REMOTE,
        "videoSize": info["video_size"],
        "previewSize": info["video_preview_size"],
        "glowColor": GLOW,
        "category": "ANIME",
        "type": "video",
        "badge": "NEW",
        "sortOrder": max_sort + 2,
        "tags": TAGS + ["interactivo"],
        "downloadCount": 0,
        "createdAt": now_iso,
        "frameCount": info["frame_count"],
        "framesPath": LIVE_FRAMES_PATH,
    }

    def upsert(entry):
        idx = next((i for i, w in enumerate(wallpapers) if w["id"] == entry["id"]), -1)
        if idx >= 0:
            print(f"  · {entry['id']} idx {idx} → replace")
            wallpapers[idx] = entry
        else:
            print(f"  · {entry['id']} append (sortOrder {entry['sortOrder']})")
            wallpapers.append(entry)

    upsert(entry_auto)
    upsert(entry_explore)
    catalog["lastUpdated"] = now_iso
    storage_put_json(LIVE_BUCKET, CATALOG_REMOTE, catalog)
    print(f"  total live ahora: {len(wallpapers)}")


def phase5_fcm():
    print("\n[5/5] FCM invalidate")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print(f"  live       -> {send_catalog_invalidate('live')}")


if __name__ == "__main__":
    print("=" * 60)
    print("Throotle Underwater — publisher (low-RAM optimized)")
    print("=" * 60)
    if not SRC_PNG.exists(): raise SystemExit(f"No existe {SRC_PNG}")
    if not SRC_MP4.exists(): raise SystemExit(f"No existe {SRC_MP4}")

    info = phase1_process_local()
    phase2_upload(info)
    phase3_insert_static(info)
    phase4_live_catalog(info)
    phase5_fcm()

    print("\n" + "=" * 60)
    print("✅ Throotle publicado")
    print("=" * 60)
    print(f"  1 static + 2 live cards (auto + explore)")
    print(f"  Frame count: {info['frame_count']} @ {EXPLORE_WIDTH}x{EXPLORE_HEIGHT}")
    print(f"  Memoria total Explore: ~{sum(f.stat().st_size for f in OUT_FRAMES_DIR.glob('frame_*.jpg'))/1024/1024:.1f} MB")
