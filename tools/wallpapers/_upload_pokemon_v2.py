"""
Pokemon v2 update:
  1) Sube pokemon_para_preview.png como NUEVA preview para los 3 wallpapers
     pokemon (static, panoramic-static, canvas_scene). Es la misma imagen
     pero más cinematográfica para el catálogo.
  2) Procesa pokemon_en_cabaña.mp4 como LIVE wallpaper (auto + explore).
  3) Asegura que pokemon_cafe_3d (canvas_scene) esté en tabla wallpapers
     para que aparezca en el grid del admin.
"""
import io, json, re, subprocess, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC_DIR = Path(r"C:/Users/lalo/Desktop/wallPapers_repo/nuevos/pokemon")
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_pokemon_v2")
SRC_PREV = SRC_DIR / "pokemon_para_preview.png"
SRC_MP4  = SRC_DIR / "pokemon_en_cabaña.mp4"

PREVIEW_REMOTE = "pokemon_preview_v2.webp"   # nuevo nombre, no pisa el viejo
PREVIEW_LIVE_REMOTE = "previews/pokemon_cafe_live_v2.webp"

LIVE_VIDEO_REMOTE = "videos/pokemon_cafe_cabana.mp4"
LIVE_FRAMES_PATH = "frames/pokemon_cafe_cabana_explore"

LIVE_AUTO_ID = "pokemon_cafe_cabana_auto"
LIVE_EXPLORE_ID = "pokemon_cafe_cabana_explore"

EXPLORE_FPS = 2.5
EXPLORE_W, EXPLORE_H = 720, 1280

TAGS = ["pokemon", "pikachu", "cafe", "chimenea", "casa", "cozy",
        "anime", "nintendo", "cabana", "lluvia"]
GLOW = "#FFCB05"


def load_sk():
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)
SK = load_sk()

def put(bucket, remote, local, ct):
    body = local.read_bytes() if isinstance(local, Path) else local
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
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
    req.add_header("Content-Type", "application/json"); req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status}")

def run(cmd):
    print(f"  $ {cmd[0]} ...")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"    STDERR: {r.stderr[-300:]}")
        raise SystemExit(f"cmd failed: {r.returncode}")


def phase1_preview():
    from PIL import Image
    print("\n[1/5] Process new preview")
    WORK.mkdir(parents=True, exist_ok=True)
    img = Image.open(SRC_PREV).convert("RGB")
    out_full = WORK / "pokemon_preview_full.webp"
    img.save(out_full, "WEBP", quality=90, method=6)
    out_small = WORK / "pokemon_preview_small.webp"
    prev = img.copy(); prev.thumbnail((540, 1170), Image.LANCZOS)
    prev.save(out_small, "WEBP", quality=85, method=6)
    print(f"  full {img.width}x{img.height} -> {out_full.stat().st_size:,} B")
    print(f"  small {prev.width}x{prev.height} -> {out_small.stat().st_size:,} B")
    put("wallpaper-images", PREVIEW_REMOTE, out_small, "image/webp")
    put("wallpaper-videos", PREVIEW_LIVE_REMOTE, out_small, "image/webp")
    return {"preview_full": out_full, "preview_small": out_small,
            "preview_size": out_small.stat().st_size,
            "full_size": out_full.stat().st_size,
            "w": img.width, "h": img.height}


def phase2_repoint_existing_pokemon(info):
    """Update both Postgres entries (pokemon_cafe + pokemon_cafe_3d) to point
    at the new preview. Also INSERT pokemon_cafe_3d (canvas_scene) into the
    wallpapers table so it appears in the admin grid (currently it's only in
    catalog_index.json which the admin doesn't render in WALLPAPERS tab)."""
    print("\n[2/5] Update Postgres rows (preview repoint + insert canvas_scene)")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect
    conn = connect(); cur = conn.cursor()

    # Update pokemon_cafe (static) preview to new one
    cur.execute("""
        UPDATE wallpapers SET preview_path = %s, preview_size = %s, updated_at = now()
        WHERE id = 'pokemon_cafe' RETURNING id;
    """, (PREVIEW_REMOTE, info["preview_size"]))
    print(f"  · pokemon_cafe preview updated: {cur.fetchall()}")

    # INSERT pokemon_cafe_3d_cozy as proxy for the canvas_scene so it appears
    # in admin grid. The actual scene_spec stays in wallpaper-scenes; this row
    # is just metadata for listing/stats purposes.
    cur.execute("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM wallpapers;")
    next_sort = cur.fetchone()[0]
    cur.execute("""
        INSERT INTO wallpapers (
            id, name, description, type, category, tags,
            image_path, preview_path, image_size, preview_size,
            glow_color, badge, sort_order, featured, trending_score,
            published, daily_eligible, author_name, media_width, media_height
        ) VALUES (
            'pokemon_cafe_3d', 'Pokemon Cafe 3D',
            'Pikachu tomando cafecito junto a la chimenea con sprites animados — escena 3D parallax',
            'static'::wallpaper_type, 'SCENES'::wallpaper_category, %s,
            'pokemon_cafe_3d.webp', %s, 191800, %s,
            %s, 'NEW'::wallpaper_badge, %s, true, 0,
            true, false, 'Pixora Studio', %s, %s
        )
        ON CONFLICT (id) DO UPDATE SET
            preview_path = EXCLUDED.preview_path,
            preview_size = EXCLUDED.preview_size,
            featured = EXCLUDED.featured,
            published = EXCLUDED.published,
            updated_at = now()
        RETURNING id;
    """, (TAGS, PREVIEW_REMOTE, info["preview_size"], GLOW, next_sort, 1080, 1920))
    print(f"  · pokemon_cafe_3d upserted: {cur.fetchall()}")
    conn.commit(); cur.close(); conn.close()


def phase3_live_video(info):
    print("\n[3/5] Process MP4 + frames + uploads")
    out_mp4 = WORK / "pokemon_cafe_cabana.mp4"
    out_prev_anim = WORK / "pokemon_cafe_cabana_preview_anim.webp"
    out_frames = WORK / "frames"
    out_frames.mkdir(exist_ok=True)
    for f in out_frames.glob("frame_*.jpg"): f.unlink()
    if out_mp4.exists(): out_mp4.unlink()
    if out_prev_anim.exists(): out_prev_anim.unlink()
    # Re-encode MP4: no audio, 2 Mbps baseline
    run([
        "ffmpeg", "-y", "-i", str(SRC_MP4),
        "-an", "-c:v", "libx264", "-profile:v", "baseline", "-level", "4.0",
        "-b:v", "2000k", "-maxrate", "2500k", "-bufsize", "4000k",
        "-movflags", "+faststart", "-pix_fmt", "yuv420p",
        "-loglevel", "error", str(out_mp4),
    ])
    video_size = out_mp4.stat().st_size
    print(f"  · mp4: {video_size:,} B")
    # Animated preview WebP (480 sq, 6fps)
    run([
        "ffmpeg", "-y", "-i", str(out_mp4),
        "-vf", "scale=480:480:force_original_aspect_ratio=increase,crop=480:480,fps=6",
        "-loop", "0", "-lossless", "0", "-compression_level", "6", "-q:v", "50",
        "-loglevel", "error", str(out_prev_anim),
    ])
    prev_anim_size = out_prev_anim.stat().st_size
    print(f"  · preview anim: {prev_anim_size:,} B")
    # Explore frames (8 frames @ 720p — low-RAM)
    run([
        "ffmpeg", "-y", "-i", str(out_mp4),
        "-vf", f"fps={EXPLORE_FPS},scale={EXPLORE_W}:{EXPLORE_H}",
        "-q:v", "4", "-loglevel", "error",
        str(out_frames / "frame_%04d.jpg"),
    ])
    frames = sorted(out_frames.glob("frame_*.jpg"))
    print(f"  · {len(frames)} explore frames")

    # Upload
    put("wallpaper-videos", LIVE_VIDEO_REMOTE, out_mp4, "video/mp4")
    put("wallpaper-videos", f"previews/{LIVE_AUTO_ID}_preview.webp", out_prev_anim, "image/webp")
    for f in frames:
        put("wallpaper-videos", f"{LIVE_FRAMES_PATH}/{f.name}", f, "image/jpeg")

    return {"video_size": video_size, "preview_anim_size": prev_anim_size,
            "frame_count": len(frames)}


def phase4_live_catalog(info):
    print("\n[4/5] UPSERT live_wallpaper_catalog.json (2 cards)")
    cat = get_json("wallpaper-videos", "live_wallpaper_catalog.json")
    waps = cat["wallpapers"]
    max_sort = max((w.get("sortOrder", 0) for w in waps), default=0)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    entry_auto = {
        "id": LIVE_AUTO_ID, "name": "Pokemon · Cabaña",
        "description": "Pikachu en su cabaña tomando café junto a la chimenea — video looping",
        "videoFile": LIVE_VIDEO_REMOTE,
        "previewFile": f"previews/{LIVE_AUTO_ID}_preview.webp",
        "videoSize": info["video_size"], "previewSize": info["preview_anim_size"],
        "glowColor": GLOW, "category": "ANIME", "type": "video",
        "badge": "NEW", "sortOrder": max_sort + 1, "tags": TAGS,
        "downloadCount": 0, "createdAt": now_iso,
    }
    entry_explore = dict(entry_auto)
    entry_explore.update({
        "id": LIVE_EXPLORE_ID, "name": "Pokemon · Cabaña · Explore",
        "description": "Pikachu en cabaña — toca y desliza para explorar cuadro a cuadro",
        "tags": TAGS + ["interactivo"],
        "sortOrder": max_sort + 2,
        "frameCount": info["frame_count"], "framesPath": LIVE_FRAMES_PATH,
    })
    for entry in (entry_auto, entry_explore):
        idx = next((i for i, w in enumerate(waps) if w["id"] == entry["id"]), -1)
        if idx >= 0:
            waps[idx] = entry; print(f"  · {entry['id']} replace")
        else:
            waps.append(entry); print(f"  · {entry['id']} append (sortOrder {entry['sortOrder']})")
    cat["lastUpdated"] = now_iso
    put_json("wallpaper-videos", "live_wallpaper_catalog.json", cat)


def phase5_fcm():
    print("\n[5/5] FCM invalidate")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    print(f"  wallpapers -> {send_catalog_invalidate('wallpapers')}")
    print(f"  live       -> {send_catalog_invalidate('live')}")


if __name__ == "__main__":
    print("=" * 60); print("Pokemon v2 — preview update + new live video"); print("=" * 60)
    if not SRC_PREV.exists(): raise SystemExit(f"No existe {SRC_PREV}")
    if not SRC_MP4.exists(): raise SystemExit(f"No existe {SRC_MP4}")
    info = phase1_preview()
    phase2_repoint_existing_pokemon(info)
    vinfo = phase3_live_video(info)
    phase4_live_catalog(vinfo)
    phase5_fcm()
    print("\n" + "=" * 60); print("Pokemon v2 publicado"); print("=" * 60)
