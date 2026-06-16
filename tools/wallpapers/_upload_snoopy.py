"""
Pixora content publisher — Snoopy en la Playa.

Inputs: C:/Users/lalo/Desktop/wallPapers_repo/nuevos/snoopy/
  - snoopy_enLaPlaya.png  (5.2 MB)
  - snoopy_enLaPlaya.mp4  (9.2 MB, con audio)

Pipeline:
  1. Procesamiento local con Pillow + ffmpeg:
     a) PNG -> WebP q90 + preview 540x1170 WebP
     b) MP4 -> H.264 baseline sin audio, 2 Mbps target, +faststart
     c) MP4 -> preview WebP animado 720x720
     d) MP4 -> 24 frames JPG (fps=4) para modo Explore
  2. Upload a Supabase Storage:
     - wallpaper-images/snoopy_enLaPlaya.webp + preview
     - wallpaper-videos/videos/snoopy_enLaPlaya.mp4 + preview
     - wallpaper-videos/frames/snoopy_beach_explore/frame_NNNN.jpg
  3. INSERT en Postgres `wallpapers` (static)
  4. UPSERT en live_wallpaper_catalog.json (2 entries: auto + explore)
  5. FCM push catalog_invalidate

Run: python tools/wallpapers/_upload_snoopy.py
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# UTF-8 stdout en Windows
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# ───────────────────── config ─────────────────────
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/snoopy")
WORK_DIR = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_snoopy")

SRC_PNG = SRC_DIR / "snoopy_enLaPlaya.png"
SRC_MP4 = SRC_DIR / "snoopy_enLaPlaya.mp4"

# Outputs locales
OUT_STATIC_WEBP = WORK_DIR / "snoopy_enLaPlaya.webp"
OUT_STATIC_PREVIEW = WORK_DIR / "snoopy_enLaPlaya_preview.webp"
OUT_VIDEO_MP4 = WORK_DIR / "snoopy_enLaPlaya.mp4"
OUT_VIDEO_PREVIEW = WORK_DIR / "snoopy_enLaPlaya_preview.webp"  # used by live entries
OUT_FRAMES_DIR = WORK_DIR / "frames"

# Remote paths
STATIC_BUCKET = "wallpaper-images"
LIVE_BUCKET = "wallpaper-videos"

STATIC_IMG_REMOTE = "snoopy_enLaPlaya.webp"
STATIC_PREV_REMOTE = "snoopy_enLaPlaya_preview.webp"
LIVE_VIDEO_REMOTE = "videos/snoopy_enLaPlaya.mp4"
LIVE_PREV_REMOTE = "previews/snoopy_enLaPlaya_preview.webp"
LIVE_FRAMES_PATH = "frames/snoopy_beach_explore"  # remote folder

CATALOG_REMOTE = "live_wallpaper_catalog.json"

# IDs
STATIC_ID = "snoopy_beach"
LIVE_AUTO_ID = "snoopy_beach_auto"
LIVE_EXPLORE_ID = "snoopy_beach_explore"

TAGS = ["anime", "snoopy", "playa", "verano", "cute", "beagle", "relajacion"]
GLOW = "#FF6B6B"  # rojo del salvavidas


# ───────────────────── helpers ─────────────────────
def load_service_key() -> str:
    keys = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", keys)
    if not m:
        raise SystemExit("Service Role Key no encontrado en KEYS_LOCAL.md")
    return m.group(1)


SERVICE_KEY = load_service_key()


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check and r.returncode != 0:
        print(f"    STDOUT: {r.stdout[-500:]}")
        print(f"    STDERR: {r.stderr[-500:]}")
        raise SystemExit(f"Comando falló (exit {r.returncode})")
    return r


def storage_put(bucket: str, remote: str, local: Path, content_type: str) -> int:
    body = local.read_bytes()
    url = f"{PROJECT}/storage/v1/object/{bucket}/{remote}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", content_type)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote}  -> {r.status} ({len(body):,} bytes)")
    return len(body)


def storage_get_json(bucket: str, remote: str) -> dict:
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def storage_put_json(bucket: str, remote: str, data: dict) -> None:
    payload = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    url = f"{PROJECT}/storage/v1/object/{bucket}/{remote}"
    req = urllib.request.Request(url, data=payload, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote}  -> {r.status} (JSON catalog)")


# ───────────────────── FASE 1: procesar local ─────────────────────
def phase1_process_local() -> dict:
    """Genera todos los outputs locales. Returns dict con sizes + dims."""
    from PIL import Image

    print("\n[1/5] Procesamiento local")
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    OUT_FRAMES_DIR.mkdir(parents=True, exist_ok=True)

    info = {}

    # 1a. PNG -> WebP
    print("  · PNG -> WebP (q90)")
    img = Image.open(SRC_PNG).convert("RGBA")
    info["width"] = img.width
    info["height"] = img.height
    img.save(OUT_STATIC_WEBP, "WEBP", quality=90, method=6)
    info["static_webp_size"] = OUT_STATIC_WEBP.stat().st_size
    print(f"    {img.width}x{img.height}, {info['static_webp_size']:,} bytes")

    # 1b. PNG preview 540x1170 WebP
    print("  · PNG preview 540x1170 WebP")
    prev = img.copy()
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_STATIC_PREVIEW, "WEBP", quality=85, method=6)
    info["static_preview_size"] = OUT_STATIC_PREVIEW.stat().st_size
    print(f"    {prev.width}x{prev.height}, {info['static_preview_size']:,} bytes")

    # 1c. MP4 re-encode H.264 sin audio
    print("  · MP4 -> H.264 baseline sin audio, ~2 Mbps")
    if OUT_VIDEO_MP4.exists():
        OUT_VIDEO_MP4.unlink()
    run([
        "ffmpeg", "-y", "-i", str(SRC_MP4),
        "-an",  # sin audio
        "-c:v", "libx264", "-profile:v", "baseline", "-level", "4.0",
        "-b:v", "2000k", "-maxrate", "2500k", "-bufsize", "4000k",
        "-movflags", "+faststart",
        "-pix_fmt", "yuv420p",
        "-loglevel", "error",
        str(OUT_VIDEO_MP4),
    ])
    info["video_size"] = OUT_VIDEO_MP4.stat().st_size
    print(f"    {info['video_size']:,} bytes")

    # 1d. Preview WebP animado 720x720
    print("  · Preview WebP animado 720x720")
    if OUT_VIDEO_PREVIEW.exists():
        OUT_VIDEO_PREVIEW.unlink()
    run([
        "ffmpeg", "-y", "-i", str(OUT_VIDEO_MP4),
        "-vf", "scale=720:720:force_original_aspect_ratio=increase,crop=720:720,fps=8",
        "-loop", "0", "-lossless", "0", "-compression_level", "6", "-q:v", "70",
        "-loglevel", "error",
        str(OUT_VIDEO_PREVIEW),
    ])
    info["video_preview_size"] = OUT_VIDEO_PREVIEW.stat().st_size
    print(f"    {info['video_preview_size']:,} bytes")

    # 1e. Extraer 24 frames fps=4 (6s × 4 = 24)
    print("  · Extraer 24 frames JPG (fps=4)")
    # limpia frames previos
    for f in OUT_FRAMES_DIR.glob("frame_*.jpg"):
        f.unlink()
    run([
        "ffmpeg", "-y", "-i", str(OUT_VIDEO_MP4),
        "-vf", "fps=4",
        "-q:v", "3",
        "-loglevel", "error",
        str(OUT_FRAMES_DIR / "frame_%04d.jpg"),
    ])
    frames = sorted(OUT_FRAMES_DIR.glob("frame_*.jpg"))
    info["frame_count"] = len(frames)
    total = sum(f.stat().st_size for f in frames)
    print(f"    {len(frames)} frames, total {total:,} bytes")
    return info


# ───────────────────── FASE 2: upload Storage ─────────────────────
def phase2_upload_storage(info: dict) -> None:
    print("\n[2/5] Upload a Supabase Storage")
    # Static
    storage_put(STATIC_BUCKET, STATIC_IMG_REMOTE, OUT_STATIC_WEBP, "image/webp")
    storage_put(STATIC_BUCKET, STATIC_PREV_REMOTE, OUT_STATIC_PREVIEW, "image/webp")
    # Live video + preview
    storage_put(LIVE_BUCKET, LIVE_VIDEO_REMOTE, OUT_VIDEO_MP4, "video/mp4")
    storage_put(LIVE_BUCKET, LIVE_PREV_REMOTE, OUT_VIDEO_PREVIEW, "image/webp")
    # Frames para explore
    print(f"  · Uploading {info['frame_count']} frames")
    for f in sorted(OUT_FRAMES_DIR.glob("frame_*.jpg")):
        remote = f"{LIVE_FRAMES_PATH}/{f.name}"
        storage_put(LIVE_BUCKET, remote, f, "image/jpeg")


# ───────────────────── FASE 3: Postgres INSERT static ─────────────────────
def phase3_insert_static(info: dict) -> None:
    print("\n[3/5] INSERT en Postgres wallpapers (static)")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect

    conn = connect()
    cur = conn.cursor()

    # Compute next sort_order
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    print(f"  next sort_order: {next_sort}")

    # Upsert (ON CONFLICT id DO UPDATE → permite re-correr el script)
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
        "Snoopy en la Playa",
        "Snoopy disfrutando un día soleado, flotando en su salvavidas rojo "
        "en una playa tropical al atardecer · ilustración estilo anime relajada",
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
    inserted_id = cur.fetchone()[0]
    conn.commit()
    print(f"  upserted: {inserted_id}")
    cur.close()
    conn.close()


# ───────────────────── FASE 4: live catalog JSON ─────────────────────
def phase4_update_live_catalog(info: dict) -> None:
    print("\n[4/5] UPSERT en live_wallpaper_catalog.json (2 entries)")
    catalog = storage_get_json(LIVE_BUCKET, CATALOG_REMOTE)
    wallpapers = catalog["wallpapers"]

    max_sort = max((w.get("sortOrder", 0) for w in wallpapers), default=0)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    entry_auto = {
        "id": LIVE_AUTO_ID,
        "name": "Snoopy en la Playa",
        "description": "Snoopy flotando en su salvavidas rojo al atardecer · video looping suave",
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
        "name": "Snoopy en la Playa · Explore",
        "description": "Snoopy en la playa · toca y desliza para explorar la escena cuadro a cuadro",
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

    def upsert(entry: dict) -> None:
        idx = next((i for i, w in enumerate(wallpapers) if w["id"] == entry["id"]), -1)
        if idx >= 0:
            print(f"  · {entry['id']} ya existía (idx {idx}) — replace")
            wallpapers[idx] = entry
        else:
            print(f"  · {entry['id']} append (sortOrder {entry['sortOrder']})")
            wallpapers.append(entry)

    upsert(entry_auto)
    upsert(entry_explore)

    catalog["lastUpdated"] = now_iso
    storage_put_json(LIVE_BUCKET, CATALOG_REMOTE, catalog)
    print(f"  total live wallpapers ahora: {len(wallpapers)}")


# ───────────────────── FASE 5: FCM invalidate ─────────────────────
def phase5_fcm_invalidate() -> None:
    print("\n[5/5] FCM push catalog_invalidate")
    try:
        from _fcm_push import send_to_topic  # type: ignore
    except Exception as e:
        print(f"  WARN: no pude importar _fcm_push.send_to_topic ({e})")
        print("  manual: ejecuta `python tools/wallpapers/_fcm_push.py` para invalidar caches")
        return
    try:
        send_to_topic(
            "catalog_invalidate",
            "Snoopy nuevo en Anime + Live",
            "Static + 2 live wallpapers de Snoopy en la Playa",
            data={"reason": "snoopy_upload"},
        )
        print("  FCM enviado")
    except Exception as e:
        print(f"  WARN: FCM falló: {e}")


# ───────────────────── main ─────────────────────
if __name__ == "__main__":
    print("=" * 60)
    print("Snoopy en la Playa — publisher")
    print("=" * 60)

    if not SRC_PNG.exists():
        raise SystemExit(f"No existe {SRC_PNG}")
    if not SRC_MP4.exists():
        raise SystemExit(f"No existe {SRC_MP4}")

    info = phase1_process_local()
    phase2_upload_storage(info)
    phase3_insert_static(info)
    phase4_update_live_catalog(info)
    phase5_fcm_invalidate()

    print("\n" + "=" * 60)
    print("✅ Snoopy publicado: 1 static (ANIME) + 2 live (auto + explore)")
    print("=" * 60)
    print("Próximos pasos:")
    print("  1. Cold-start la app en Samsung — debería ver los 3 nuevos en /15s")
    print("  2. Verificar Anime grid → static · LIVE grid → 2 cards Snoopy")
    print("  3. Probar Apply en cada modo")
