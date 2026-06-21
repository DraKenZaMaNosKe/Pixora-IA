"""
Pixora content publisher — Viaje en tren por el bosque
(chava joven asomada a la ventana + gatitos + pericos dentro del tren).

Source: C:/Users/lalo/Desktop/wallPapers_repo/nuevos/viajeentren/
  - viajandoentren_porelbosque.png            (1080x1986 portrait)
  - viajandoentren_porelbosque_panoramico.png (4128x1024 ultra-wide,
                                               interior del tren con
                                               personas + animales)
  - viaje_en_tren_porelbosque_chavajoven_video.mp4 (live loop)

Outputs (3 cards — Eduardo pidió SIN explore):
  1. STATIC portrait   → tren_bosque_chava            → wallpaper-images
  2. PANORAMIC         → tren_bosque_chava_pano       → wallpaper-images
  3. LIVE autoplay     → tren_bosque_chava_auto       → wallpaper-videos

Sin frames de explore, sin entry _explore en catalog.
"""
from __future__ import annotations
import json, re, subprocess, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/viajeentren")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_tren")

SRC_STATIC = SRC / "viajandoentren_porelbosque.png"
SRC_PANO = SRC / "viajandoentren_porelbosque_panoramico.png"
SRC_MP4 = SRC / "viaje_en_tren_porelbosque_chavajoven_video.mp4"

# Outputs locales
OUT_STATIC = WORK / "tren_bosque_chava.webp"
OUT_PREVIEW = WORK / "tren_bosque_chava_preview.webp"
OUT_PANO = WORK / "tren_bosque_chava_pano.webp"
OUT_PANO_PREVIEW = WORK / "tren_bosque_chava_pano_preview.webp"
OUT_MP4 = WORK / "tren_bosque_chava.mp4"
OUT_VIDEO_PREVIEW = WORK / "tren_bosque_chava_video_preview.webp"

# Remote storage paths
IMG_BUCKET = "wallpaper-images"
LIVE_BUCKET = "wallpaper-videos"
STATIC_REMOTE = "tren_bosque_chava.webp"
STATIC_PREV_REMOTE = "tren_bosque_chava_preview.webp"
PANO_REMOTE = "tren_bosque_chava_pano.webp"
PANO_PREV_REMOTE = "tren_bosque_chava_pano_preview.webp"
LIVE_VIDEO_REMOTE = "videos/tren_bosque_chava.mp4"
LIVE_PREV_REMOTE = "previews/tren_bosque_chava_preview.webp"

CATALOG_REMOTE = "live_wallpaper_catalog.json"

STATIC_ID = "tren_bosque_chava"
PANO_ID = "tren_bosque_chava_pano"
LIVE_AUTO_ID = "tren_bosque_chava_auto"

TAGS = ["tren", "bosque", "viaje", "naturaleza", "gatitos", "perros",
        "pericos", "animales", "cozy", "anime", "ilustracion",
        "ventana", "vapor", "primavera"]
GLOW = "#7ECB6E"  # verde fresco del bosque


def load_sk():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)
SK = load_sk()


def run(cmd):
    print(f"  $ {cmd[0]} ...")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"    STDERR: {r.stderr[-400:]}")
        raise SystemExit(f"cmd failed exit {r.returncode}")


def put(bucket, remote, local, ct):
    body = local.read_bytes() if isinstance(local, Path) else local
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} ({len(body):,} B)")


def get_json(bucket, remote):
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{remote}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def put_json(bucket, remote, data):
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} (catalog)")


# ───────────────────── FASE 1: process ─────────────────────
def phase1_process():
    from PIL import Image
    print("\n[1/5] Procesamiento local")
    WORK.mkdir(parents=True, exist_ok=True)
    info = {}

    # 1a. Static portrait WebP
    print("  · Static portrait PNG -> WebP")
    img = Image.open(SRC_STATIC).convert("RGB")
    info["static_w"], info["static_h"] = img.width, img.height
    img.save(OUT_STATIC, "WEBP", quality=90, method=6)
    info["static_size"] = OUT_STATIC.stat().st_size
    print(f"    {img.width}x{img.height} -> {info['static_size']:,} B")

    # 1b. Preview cinematic (downscale del static; Eduardo no mandó preview aparte)
    print("  · Preview cinematic (downscale del static) -> WebP small")
    prev = Image.open(SRC_STATIC).convert("RGB")
    prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(OUT_PREVIEW, "WEBP", quality=85, method=6)
    info["preview_size"] = OUT_PREVIEW.stat().st_size
    print(f"    {prev.width}x{prev.height} -> {info['preview_size']:,} B")

    # 1c. Panoramic WebP full
    print("  · Panoramic PNG -> WebP (ultra-wide 4128x1024)")
    pano = Image.open(SRC_PANO).convert("RGB")
    info["pano_w"], info["pano_h"] = pano.width, pano.height
    ratio = pano.width / pano.height
    print(f"    source dims {pano.width}x{pano.height} (ratio {ratio:.2f}:1)")
    pano.save(OUT_PANO, "WEBP", quality=90, method=6)
    info["pano_size"] = OUT_PANO.stat().st_size

    # 1d. Panoramic preview (1080-wide)
    pano_prev = pano.copy()
    pano_prev.thumbnail((1080, 1080), Image.LANCZOS)
    pano_prev.save(OUT_PANO_PREVIEW, "WEBP", quality=82, method=6)
    info["pano_prev_size"] = OUT_PANO_PREVIEW.stat().st_size
    print(f"    pano {info['pano_size']:,} B  · preview {info['pano_prev_size']:,} B")

    # 1e. MP4 re-encode sin audio
    print("  · MP4 -> H.264 baseline 2Mbps sin audio")
    if OUT_MP4.exists(): OUT_MP4.unlink()
    run([
        "ffmpeg", "-y", "-i", str(SRC_MP4),
        "-an", "-c:v", "libx264", "-profile:v", "baseline", "-level", "4.0",
        "-b:v", "2000k", "-maxrate", "2500k", "-bufsize", "4000k",
        "-movflags", "+faststart", "-pix_fmt", "yuv420p",
        "-loglevel", "error", str(OUT_MP4),
    ])
    info["video_size"] = OUT_MP4.stat().st_size
    print(f"    {info['video_size']:,} B")

    # 1f. Animated preview WebP (480 sq, 6fps)
    if OUT_VIDEO_PREVIEW.exists(): OUT_VIDEO_PREVIEW.unlink()
    run([
        "ffmpeg", "-y", "-i", str(OUT_MP4),
        "-vf", "scale=480:480:force_original_aspect_ratio=increase,crop=480:480,fps=6",
        "-loop", "0", "-lossless", "0", "-compression_level", "6", "-q:v", "50",
        "-loglevel", "error", str(OUT_VIDEO_PREVIEW),
    ])
    info["video_prev_size"] = OUT_VIDEO_PREVIEW.stat().st_size
    print(f"    video preview {info['video_prev_size']:,} B")

    return info


# ───────────────────── FASE 2: upload ─────────────────────
def phase2_upload(info):
    print("\n[2/5] Upload Supabase Storage")
    put(IMG_BUCKET, STATIC_REMOTE, OUT_STATIC, "image/webp")
    put(IMG_BUCKET, STATIC_PREV_REMOTE, OUT_PREVIEW, "image/webp")
    put(IMG_BUCKET, PANO_REMOTE, OUT_PANO, "image/webp")
    put(IMG_BUCKET, PANO_PREV_REMOTE, OUT_PANO_PREVIEW, "image/webp")
    put(LIVE_BUCKET, LIVE_VIDEO_REMOTE, OUT_MP4, "video/mp4")
    put(LIVE_BUCKET, LIVE_PREV_REMOTE, OUT_VIDEO_PREVIEW, "image/webp")


# ───────────────────── FASE 3: Postgres ─────────────────────
def phase3_postgres(info):
    print("\n[3/5] INSERT Postgres (static + panoramic)")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect
    conn = connect(); cur = conn.cursor()

    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    print(f"  · static sort_order: {next_sort}")
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'static'::wallpaper_type, 'NATURE'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, true, 0,
            true, true, 'Pixora Studio', %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description,
            tags=EXCLUDED.tags, image_path=EXCLUDED.image_path,
            preview_path=EXCLUDED.preview_path, image_size=EXCLUDED.image_size,
            preview_size=EXCLUDED.preview_size, glow_color=EXCLUDED.glow_color,
            featured=EXCLUDED.featured, published=EXCLUDED.published,
            daily_eligible=EXCLUDED.daily_eligible,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            updated_at=now()
        RETURNING id;
    """, (
        STATIC_ID, "Viaje en tren · Bosque",
        "Chava joven asomada a la ventana de un tren atravesando un bosque verde — luz cálida del atardecer entre los árboles",
        TAGS, STATIC_REMOTE, STATIC_PREV_REMOTE,
        info["static_size"], info["preview_size"], GLOW, next_sort,
        info["static_w"], info["static_h"]
    ))
    print(f"  · upserted static: {cur.fetchone()[0]}")

    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    print(f"  · panoramic sort_order: {next_sort}")
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            %s, %s, %s, 'panoramic'::wallpaper_type, 'PANORAMIC'::wallpaper_category, %s,
            %s, %s, %s, %s, %s, 'NEW'::wallpaper_badge, %s, true, 0,
            true, true, 'Pixora Studio', %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            name=EXCLUDED.name, description=EXCLUDED.description,
            tags=EXCLUDED.tags, image_path=EXCLUDED.image_path,
            preview_path=EXCLUDED.preview_path, image_size=EXCLUDED.image_size,
            preview_size=EXCLUDED.preview_size, glow_color=EXCLUDED.glow_color,
            featured=EXCLUDED.featured, published=EXCLUDED.published,
            daily_eligible=EXCLUDED.daily_eligible,
            media_width=EXCLUDED.media_width, media_height=EXCLUDED.media_height,
            updated_at=now()
        RETURNING id;
    """, (
        PANO_ID, "Viaje en tren · Panorámica",
        "Interior panorámico del tren — chava, gatitos durmiendo, pericos, plantas colgantes y pasajeros en armonía con los animales — desliza tu home para ver todo el vagón",
        TAGS + ["panoramico", "interior"], PANO_REMOTE, PANO_PREV_REMOTE,
        info["pano_size"], info["pano_prev_size"], GLOW, next_sort,
        info["pano_w"], info["pano_h"]
    ))
    print(f"  · upserted panoramic: {cur.fetchone()[0]}")
    conn.commit(); cur.close(); conn.close()


# ───────────────────── FASE 4: live catalog ─────────────────────
def phase4_live_catalog(info):
    print("\n[4/5] UPSERT live_wallpaper_catalog.json (solo auto, sin explore)")
    cat = get_json(LIVE_BUCKET, CATALOG_REMOTE)
    waps = cat["wallpapers"]
    max_sort = max((w.get("sortOrder", 0) for w in waps), default=0)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    entry_auto = {
        "id": LIVE_AUTO_ID, "name": "Viaje en tren · Bosque",
        "description": "Chava asomada a la ventana del tren atravesando el bosque — auto loop suave",
        "videoFile": LIVE_VIDEO_REMOTE, "previewFile": LIVE_PREV_REMOTE,
        "videoSize": info["video_size"], "previewSize": info["video_prev_size"],
        "glowColor": GLOW, "category": "NATURE", "type": "video",
        "badge": "NEW", "sortOrder": max_sort + 1, "tags": TAGS,
        "downloadCount": 0, "createdAt": now_iso,
    }

    idx = next((i for i, w in enumerate(waps) if w["id"] == entry_auto["id"]), -1)
    if idx >= 0:
        waps[idx] = entry_auto; print(f"  · {entry_auto['id']} replace")
    else:
        waps.append(entry_auto); print(f"  · {entry_auto['id']} append (sortOrder {entry_auto['sortOrder']})")
    cat["lastUpdated"] = now_iso
    put_json(LIVE_BUCKET, CATALOG_REMOTE, cat)
    print(f"  · total live cards: {len(waps)}")


# ───────────────────── FASE 5: FCM ─────────────────────
def phase5_fcm():
    print("\n[5/5] FCM invalidate")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print(f"  live       -> {send_catalog_invalidate('live')}")


if __name__ == "__main__":
    print("=" * 60); print("Viaje en tren — 3 cards publisher (static + pano + live auto)")
    print("=" * 60)
    for src in (SRC_STATIC, SRC_PANO, SRC_MP4):
        if not src.exists(): raise SystemExit(f"No existe {src}")
    info = phase1_process()
    phase2_upload(info)
    phase3_postgres(info)
    phase4_live_catalog(info)
    phase5_fcm()
    print("\n" + "=" * 60)
    print("Viaje en tren publicado · static + panoramic + live auto")
    print(f"  · static {info['static_w']}x{info['static_h']}")
    print(f"  · panoramic {info['pano_w']}x{info['pano_h']} (ratio {info['pano_w']/info['pano_h']:.2f}:1)")
    print(f"  · live video {info['video_size']:,} B")
    print("=" * 60)
