"""
Pixora content publisher — Finn & Jake (Adventure Time, sleeping forest set).

Source: C:/Users/lalo/Desktop/wallPapers_repo/nuevos/finyjake/
  - finyjake_descansandoenbosque_wallpaper.png      (4.3 MB, 1080x2340 portrait)
  - panoramico_finyjakedescansandobosque.png        (7.75 MB, 4128x1024 panoramic)
  - video_finyjake_bosquedescansando_00.mp4         (9.4 MB, 1080x1986 6s 30fps)

Outputs (4 cards):
  1. Static portrait   → finyjake_sleeping_forest          → wallpaper-images (WebP)
  2. Panoramic         → finyjake_sleeping_forest_pano     → wallpaper-images (WebP)
  3. Live autoplay     → finyjake_sleeping_forest_auto     → wallpaper-videos (MP4)
  4. Live explore      → finyjake_sleeping_forest_explore  → wallpaper-videos (MP4 + 15 frames @ 720p)

LOW-RAM optimization (same as Throotle):
  · Explore: 15 frames @ 720x1280 instead of 24 @ 1080p
  · MP4 re-encoded sin audio @ 2 Mbps
  · Target: 4GB Samsung soporta switches sin lmkd-kill
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
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/finyjake")
WORK_DIR = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_finyjake")

SRC_STATIC = SRC_DIR / "finyjake_descansandoenbosque_wallpaper.png"
SRC_PANO   = SRC_DIR / "panoramico_finyjakedescansandobosque.png"
SRC_MP4    = SRC_DIR / "video_finyjake_bosquedescansando_00.mp4"

# Local outputs
OUT_STATIC_WEBP    = WORK_DIR / "finyjake_sleeping_forest.webp"
OUT_STATIC_PREVIEW = WORK_DIR / "finyjake_sleeping_forest_preview.webp"
OUT_PANO_WEBP      = WORK_DIR / "finyjake_sleeping_forest_pano.webp"
OUT_PANO_PREVIEW   = WORK_DIR / "finyjake_sleeping_forest_pano_preview.webp"
OUT_VIDEO_MP4      = WORK_DIR / "finyjake_sleeping_forest.mp4"
OUT_VIDEO_PREVIEW  = WORK_DIR / "finyjake_sleeping_forest_video_preview.webp"
OUT_FRAMES_DIR     = WORK_DIR / "frames"

# Remote paths
STATIC_BUCKET = "wallpaper-images"
LIVE_BUCKET   = "wallpaper-videos"

STATIC_IMG_REMOTE  = "finyjake_sleeping_forest.webp"
STATIC_PREV_REMOTE = "finyjake_sleeping_forest_preview.webp"
PANO_IMG_REMOTE    = "finyjake_sleeping_forest_pano.webp"
PANO_PREV_REMOTE   = "finyjake_sleeping_forest_pano_preview.webp"
LIVE_VIDEO_REMOTE  = "videos/finyjake_sleeping_forest.mp4"
LIVE_PREV_REMOTE   = "previews/finyjake_sleeping_forest_preview.webp"
LIVE_FRAMES_PATH   = "frames/finyjake_sleeping_forest_explore"

CATALOG_REMOTE = "live_wallpaper_catalog.json"

# Wallpaper IDs
STATIC_ID       = "finyjake_sleeping_forest"
PANO_ID         = "finyjake_sleeping_forest_pano"
LIVE_AUTO_ID    = "finyjake_sleeping_forest_auto"
LIVE_EXPLORE_ID = "finyjake_sleeping_forest_explore"

TAGS = ["adventure_time", "finn", "jake", "bosque", "dormir",
        "anime", "cartoon", "magico", "cute", "naturaleza"]
GLOW = "#A8E63B"  # verde lima bosque / golden hour mix

# Low-RAM Explore (same as Throotle)
EXPLORE_FPS    = 2.5
EXPLORE_WIDTH  = 720
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

    # 1a. Static portrait PNG -> WebP q90
    print("  · Static portrait PNG -> WebP q90")
    img = Image.open(SRC_STATIC).convert("RGBA")
    info["static_w"], info["static_h"] = img.width, img.height
    img.save(OUT_STATIC_WEBP, "WEBP", quality=90, method=6)
    info["static_webp_size"] = OUT_STATIC_WEBP.stat().st_size
    print(f"    {img.width}x{img.height}, {info['static_webp_size']:,} bytes")

    # 1b. Static preview (540x1170 thumb)
    print("  · Static preview 540x1170 WebP")
    prev = img.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_STATIC_PREVIEW, "WEBP", quality=85, method=6)
    info["static_preview_size"] = OUT_STATIC_PREVIEW.stat().st_size
    print(f"    {prev.width}x{prev.height}, {info['static_preview_size']:,} bytes")

    # 1c. Panoramic PNG -> WebP q90
    print("  · Panoramic PNG -> WebP q90 (ultra-wide)")
    pano = Image.open(SRC_PANO).convert("RGBA")
    info["pano_w"], info["pano_h"] = pano.width, pano.height
    ratio = pano.width / pano.height
    print(f"    source dims: {pano.width}x{pano.height} (ratio {ratio:.2f}:1)")
    if ratio < 3.0:
        print(f"    WARN: ratio {ratio:.2f} below 3:1 — scroll will feel weak")
    pano.save(OUT_PANO_WEBP, "WEBP", quality=90, method=6)
    info["pano_webp_size"] = OUT_PANO_WEBP.stat().st_size
    print(f"    {info['pano_webp_size']:,} bytes")

    # 1d. Panoramic preview (1080-wide thumb keeping aspect)
    print("  · Panoramic preview 1080-wide WebP")
    pano_prev = pano.copy()
    pano_prev.thumbnail((1080, 1080), Image.LANCZOS)
    pano_prev.save(OUT_PANO_PREVIEW, "WEBP", quality=82, method=6)
    info["pano_preview_size"] = OUT_PANO_PREVIEW.stat().st_size
    print(f"    {pano_prev.width}x{pano_prev.height}, {info['pano_preview_size']:,} bytes")

    # 1e. MP4 re-encode sin audio, 2 Mbps
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

    # 1f. Video preview animated WebP (480x480 6fps)
    print("  · Video preview 480x480 WebP animated (light)")
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

    # 1g. Extraer frames LOW-RAM (15 @ 720p)
    print(f"  · Explore frames: {EXPLORE_WIDTH}x{EXPLORE_HEIGHT} @ fps={EXPLORE_FPS}")
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
    print(f"    {len(frames)} frames, total {total:,} bytes")
    return info


# ───────────────────── FASE 2: upload Storage ─────────────────────
def phase2_upload(info):
    print("\n[2/5] Upload Supabase Storage")
    storage_put(STATIC_BUCKET, STATIC_IMG_REMOTE, OUT_STATIC_WEBP, "image/webp")
    storage_put(STATIC_BUCKET, STATIC_PREV_REMOTE, OUT_STATIC_PREVIEW, "image/webp")
    storage_put(STATIC_BUCKET, PANO_IMG_REMOTE, OUT_PANO_WEBP, "image/webp")
    storage_put(STATIC_BUCKET, PANO_PREV_REMOTE, OUT_PANO_PREVIEW, "image/webp")
    storage_put(LIVE_BUCKET, LIVE_VIDEO_REMOTE, OUT_VIDEO_MP4, "video/mp4")
    storage_put(LIVE_BUCKET, LIVE_PREV_REMOTE, OUT_VIDEO_PREVIEW, "image/webp")
    print(f"  · Uploading {info['frame_count']} explore frames")
    for f in sorted(OUT_FRAMES_DIR.glob("frame_*.jpg")):
        storage_put(LIVE_BUCKET, f"{LIVE_FRAMES_PATH}/{f.name}", f, "image/jpeg")


# ───────────────────── FASE 3: INSERT static + panoramic ─────────────────────
def phase3_insert_postgres(info):
    print("\n[3/5] INSERT Postgres wallpapers (static + panoramic)")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect

    conn = connect()
    cur = conn.cursor()

    # Static portrait — ANIME category, daily_eligible true (rota en Daily)
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    print(f"  static sort_order: {next_sort}")
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'ANIME'::wallpaper_category, %s,
            %s, %s, %s, %s,
            %s, 'NEW'::wallpaper_badge, %s, true, 0,
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
        "Finn y Jake en el bosque",
        "Finn y Jake (Adventure Time) descansando en un claro magico del bosque encantado — golden hour, particulas de luz",
        TAGS,
        STATIC_IMG_REMOTE,
        STATIC_PREV_REMOTE,
        info["static_webp_size"],
        info["static_preview_size"],
        GLOW,
        next_sort,
        "Pixora Studio",
        info["static_w"],
        info["static_h"],
    ))
    print(f"  upserted static: {cur.fetchone()[0]}")

    # Panoramic — PANORAMIC category, daily_eligible true (rota en Daily junto con static)
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort_pano = cur.fetchone()[0]
    print(f"  panoramic sort_order: {next_sort_pano}")
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'panoramic'::wallpaper_type, 'PANORAMIC'::wallpaper_category, %s,
            %s, %s, %s, %s,
            %s, 'NEW'::wallpaper_badge, %s, true, 0,
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
        PANO_ID,
        "Finn y Jake · Bosque panoramico",
        "Vista panoramica ultra-wide del claro magico con Finn y Jake durmiendo — desliza el home para explorar",
        TAGS + ["panoramico"],
        PANO_IMG_REMOTE,
        PANO_PREV_REMOTE,
        info["pano_webp_size"],
        info["pano_preview_size"],
        GLOW,
        next_sort_pano,
        "Pixora Studio",
        info["pano_w"],
        info["pano_h"],
    ))
    print(f"  upserted panoramic: {cur.fetchone()[0]}")
    conn.commit(); cur.close(); conn.close()


# ───────────────────── FASE 4: live catalog ─────────────────────
def phase4_live_catalog(info):
    print("\n[4/5] UPSERT live_wallpaper_catalog.json (auto + explore)")
    catalog = storage_get_json(LIVE_BUCKET, CATALOG_REMOTE)
    wallpapers = catalog["wallpapers"]
    max_sort = max((w.get("sortOrder", 0) for w in wallpapers), default=0)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    entry_auto = {
        "id": LIVE_AUTO_ID,
        "name": "Finn y Jake · Bosque",
        "description": "Finn y Jake dormidos en el bosque magico — video looping con particulas",
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
        "name": "Finn y Jake · Explore",
        "description": "Finn y Jake en el bosque — toca y desliza para explorar cuadro a cuadro",
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


# ───────────────────── FASE 5: FCM ─────────────────────
def phase5_fcm():
    print("\n[5/5] FCM invalidate")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print(f"  live       -> {send_catalog_invalidate('live')}")


if __name__ == "__main__":
    print("=" * 60)
    print("Finn & Jake — Adventure Time publisher (4 cards)")
    print("=" * 60)
    for src, label in [(SRC_STATIC, "static"), (SRC_PANO, "panoramic"), (SRC_MP4, "mp4")]:
        if not src.exists():
            raise SystemExit(f"No existe {label}: {src}")
    info = phase1_process_local()
    phase2_upload(info)
    phase3_insert_postgres(info)
    phase4_live_catalog(info)
    phase5_fcm()
    print("\n" + "=" * 60)
    print("Finn & Jake publicado")
    print("=" * 60)
    print(f"  Static portrait : {info['static_w']}x{info['static_h']}")
    print(f"  Panoramic       : {info['pano_w']}x{info['pano_h']} (ratio {info['pano_w']/info['pano_h']:.2f}:1)")
    print(f"  Live auto+explore: {info['frame_count']} frames @ {EXPLORE_WIDTH}x{EXPLORE_HEIGHT}")
