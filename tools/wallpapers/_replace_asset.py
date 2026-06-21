"""
Pixora · Replace an existing asset (image / panoramic / live video).

Workflow automatizado para REEMPLAZAR contenido ya publicado sin que
los usuarios tengan que actualizar el APK. Hace los 5 pasos correctos
en orden para que el self-healing del cliente detecte el cambio:

  1. Detecta el tipo del wallpaper (static / panoramic / live) consultando
     Postgres + el catálogo live de Storage.
  2. Sube el archivo nuevo al mismo path en el bucket correcto.
  3. Regenera el preview chiquito (downscale del nuevo full).
  4. UPDATE Postgres o catalog JSON con sizes + dimensions + updated_at.
  5. FCM invalidate al topic correspondiente ('wallpapers' / 'live').

El cliente, al recibir el FCM, refresca el catálogo y el ContentCache
detecta size mismatch contra el archivo cacheado en disco → re-descarga
automática. Sin reinstalar app.

Usage:
    python tools/wallpapers/_replace_asset.py <wallpaper_id> <local_file>

Examples:
    # Static wallpaper
    python tools/wallpapers/_replace_asset.py rancho_cozy_evening rancho_v2.png

    # Panoramic
    python tools/wallpapers/_replace_asset.py tren_bosque_chava_pano tren_pano_v2.png

    # Live video (mp4)
    python tools/wallpapers/_replace_asset.py rancho_cozy_evening_auto rancho_v2.mp4

Notas:
  · El path / bucket destino se infiere del registro existente — NO se
    cambia el path para que las URLs cacheadas en clientes sigan apuntando
    al mismo lugar (sólo el contenido cambia).
  · Para live videos también se regenera el preview animado 480x480 @6fps.
  · Si el wallpaper no existe en ninguna tabla, el script aborta (no
    crea entradas nuevas — para eso usa los publishers _upload_*.py).
"""
from __future__ import annotations
import argparse, json, re, subprocess, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
WORK = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_tmp_replace")
LIVE_CATALOG_BUCKET = "wallpaper-videos"
LIVE_CATALOG_PATH = "live_wallpaper_catalog.json"


def load_sk() -> str:
    txt = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
    return re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", txt).group(1)


SK = load_sk()


# ────────────────────────── helpers ──────────────────────────

def run(cmd: list[str]) -> None:
    print(f"  $ {cmd[0]} ...")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"    STDERR: {r.stderr[-400:]}")
        raise SystemExit(f"cmd failed exit {r.returncode}")


def put(bucket: str, remote: str, body: bytes, ct: str) -> None:
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body, method="PUT",
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


def put_json(bucket: str, remote: str, data: dict) -> None:
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{bucket}/{remote}",
        data=body, method="PUT",
    )
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{remote} -> {r.status} (catalog)")


def fcm_invalidate(topic: str) -> None:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _fcm_push import send_catalog_invalidate
    ok = send_catalog_invalidate(topic)
    print(f"  FCM {topic} -> {ok}")


# ────────────────────────── detection ──────────────────────────

def find_in_wallpapers(wid: str) -> dict | None:
    """Returns the row from public.wallpapers as dict, or None."""
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect
    conn = connect(); cur = conn.cursor()
    cur.execute("""
        SELECT id, type::text, category::text,
               image_path, preview_path, media_width, media_height
        FROM wallpapers WHERE id = %s
    """, (wid,))
    r = cur.fetchone()
    cur.close(); conn.close()
    if not r:
        return None
    return {
        "id": r[0], "type": r[1], "category": r[2],
        "image_path": r[3], "preview_path": r[4],
        "media_width": r[5], "media_height": r[6],
    }


def find_in_live_catalog(wid: str) -> tuple[dict, dict] | tuple[None, None]:
    """Returns (entry, full_catalog) tuple, or (None, None)."""
    cat = get_json(LIVE_CATALOG_BUCKET, LIVE_CATALOG_PATH)
    for entry in cat.get("wallpapers", []):
        if entry.get("id") == wid:
            return entry, cat
    return None, None


# ────────────────────────── replace operations ──────────────────────────

def replace_image(wid: str, src: Path, db_row: dict) -> None:
    """Static or panoramic image. Re-uploads webp + preview + UPDATE postgres."""
    from PIL import Image

    print(f"\n[image · {db_row['type']}] {wid}")
    WORK.mkdir(parents=True, exist_ok=True)

    img = Image.open(src).convert("RGB")
    w, h = img.size
    print(f"  source: {w}x{h} aspect {w/h:.2f}:1")

    # Encode WebP full (q90)
    full = WORK / db_row["image_path"]
    full.parent.mkdir(parents=True, exist_ok=True)
    img.save(full, "WEBP", quality=90, method=6)
    full_bytes = full.read_bytes()

    # Encode preview (1080-wide for panoramic, 540 for static)
    if db_row["type"] == "panoramic":
        prev = img.copy(); prev.thumbnail((1080, 1080), Image.LANCZOS)
        prev_q = 82
    else:
        prev = img.copy(); prev.thumbnail((540, 1170), Image.LANCZOS)
        prev_q = 85
    prev_path = WORK / db_row["preview_path"]
    prev_path.parent.mkdir(parents=True, exist_ok=True)
    prev.save(prev_path, "WEBP", quality=prev_q, method=6)
    prev_bytes = prev_path.read_bytes()

    # Upload both to wallpaper-images bucket (same paths as registered)
    put("wallpaper-images", db_row["image_path"], full_bytes, "image/webp")
    put("wallpaper-images", db_row["preview_path"], prev_bytes, "image/webp")

    # UPDATE Postgres
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from apply_migration import connect
    conn = connect(); cur = conn.cursor()
    cur.execute("""
        UPDATE wallpapers SET
          image_size = %s,
          preview_size = %s,
          media_width = %s,
          media_height = %s,
          updated_at = now()
        WHERE id = %s
        RETURNING id, image_size, preview_size, media_width, media_height
    """, (len(full_bytes), len(prev_bytes), w, h, wid))
    r = cur.fetchone()
    conn.commit(); cur.close(); conn.close()
    print(f"  postgres updated: image_size={r[1]} preview_size={r[2]} {r[3]}x{r[4]}")

    fcm_invalidate("wallpapers")


def replace_live_video(wid: str, src: Path, entry: dict, cat: dict) -> None:
    """Live video MP4. Re-encode H264 baseline + regen animated preview."""
    print(f"\n[live · video] {wid}")
    WORK.mkdir(parents=True, exist_ok=True)

    # Re-encode MP4 (same recipe as publishers)
    mp4 = WORK / Path(entry["videoFile"]).name
    if mp4.exists():
        mp4.unlink()
    run([
        "ffmpeg", "-y", "-i", str(src),
        "-an", "-c:v", "libx264", "-profile:v", "baseline", "-level", "4.0",
        "-b:v", "2000k", "-maxrate", "2500k", "-bufsize", "4000k",
        "-movflags", "+faststart", "-pix_fmt", "yuv420p",
        "-loglevel", "error", str(mp4),
    ])
    mp4_bytes = mp4.read_bytes()

    # Regen animated WebP preview (480 sq, 6fps)
    prev = WORK / Path(entry["previewFile"]).name
    if prev.exists():
        prev.unlink()
    run([
        "ffmpeg", "-y", "-i", str(mp4),
        "-vf", "scale=480:480:force_original_aspect_ratio=increase,crop=480:480,fps=6",
        "-loop", "0", "-lossless", "0", "-compression_level", "6", "-q:v", "50",
        "-loglevel", "error", str(prev),
    ])
    prev_bytes = prev.read_bytes()

    # Upload
    put("wallpaper-videos", entry["videoFile"], mp4_bytes, "video/mp4")
    put("wallpaper-videos", entry["previewFile"], prev_bytes, "image/webp")

    # Update catalog entry — videoSize + previewSize + lastUpdated
    for w in cat["wallpapers"]:
        if w["id"] == wid:
            w["videoSize"] = len(mp4_bytes)
            w["previewSize"] = len(prev_bytes)
            break
    cat["lastUpdated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    put_json(LIVE_CATALOG_BUCKET, LIVE_CATALOG_PATH, cat)
    print(f"  catalog updated: videoSize={len(mp4_bytes)} previewSize={len(prev_bytes)}")

    fcm_invalidate("live")


# ────────────────────────── main ──────────────────────────

def main():
    ap = argparse.ArgumentParser(description="Replace an existing Pixora asset.")
    ap.add_argument("wallpaper_id", help="ID of the wallpaper to replace")
    ap.add_argument("src", help="Local file path (PNG/JPG/MP4)")
    args = ap.parse_args()

    src = Path(args.src)
    if not src.exists():
        raise SystemExit(f"No existe: {src}")

    # 1. Buscar en wallpapers (static / panoramic)
    db_row = find_in_wallpapers(args.wallpaper_id)
    if db_row:
        replace_image(args.wallpaper_id, src, db_row)
        print("\n[OK] reemplazo completo. Self-healing dispara en próxima apertura del app.")
        return

    # 2. Buscar en live catalog
    entry, cat = find_in_live_catalog(args.wallpaper_id)
    if entry:
        if not src.suffix.lower() in (".mp4", ".mov", ".webm"):
            raise SystemExit(
                f"El ID '{args.wallpaper_id}' es un live wallpaper, esperaba MP4 pero recibí {src.suffix}"
            )
        replace_live_video(args.wallpaper_id, src, entry, cat)
        print("\n[OK] reemplazo completo. Self-healing dispara en próxima apertura del app.")
        return

    raise SystemExit(
        f"Wallpaper '{args.wallpaper_id}' no existe ni en wallpapers ni en live_catalog. "
        "Para crear contenido nuevo usa los publishers _upload_*.py"
    )


if __name__ == "__main__":
    main()
