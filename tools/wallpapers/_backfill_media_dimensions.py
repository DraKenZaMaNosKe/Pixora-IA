"""
Fase 1 backfill: llena media_width / media_height para los wallpapers
existentes en Postgres que tienen esos campos NULL.

Para cada item:
  1. GET la imagen desde Supabase Storage (image_url)
  2. Mide dimensiones con Pillow
  3. UPDATE wallpapers SET media_width=W, media_height=H WHERE id=...

Items con errores (404, imagen corrupta) se loggean pero no detienen el run.
Idempotente: solo procesa items con media_width IS NULL.
"""
from __future__ import annotations
import sys, re, io
from pathlib import Path
import urllib.request
import urllib.error

import psycopg2
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
PASSWORD = re.search(r"Database password:\s*([A-Za-z0-9_!@#%^&*+=:.\-]+)", KEYS).group(1)
DSN = f"postgresql://postgres:{PASSWORD}@db.vzuwvsmlyigjtsearxym.supabase.co:5432/postgres"

STORAGE_BASE = "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public/wallpaper-images/"


def measure(url: str) -> tuple[int, int]:
    """GET image and return (width, height). Raises on error."""
    req = urllib.request.Request(url, headers={"User-Agent": "Pixora-Backfill/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = r.read()
    img = Image.open(io.BytesIO(data))
    return img.width, img.height


def main():
    conn = psycopg2.connect(DSN, connect_timeout=10)
    conn.autocommit = False
    cur = conn.cursor()

    # Items pending backfill
    cur.execute("""
        SELECT id, image_path
        FROM public.wallpapers
        WHERE media_width IS NULL OR media_height IS NULL
        ORDER BY created_at DESC
    """)
    rows = cur.fetchall()
    total = len(rows)
    print(f"Pendientes de backfill: {total}")
    if total == 0:
        print("Nada que hacer — ya todos tienen dimensiones.")
        return

    ok = err = 0
    errors = []
    for i, (wid, image_path) in enumerate(rows, 1):
        url = STORAGE_BASE + image_path
        try:
            w, h = measure(url)
            cur.execute(
                "UPDATE public.wallpapers SET media_width=%s, media_height=%s, updated_at=now() WHERE id=%s",
                (w, h, wid),
            )
            ok += 1
            if i % 25 == 0:
                conn.commit()
                print(f"  [{i:>3}/{total}] {wid:<40}  {w}x{h}  (commit)")
        except urllib.error.HTTPError as e:
            err += 1
            errors.append((wid, f"HTTP {e.code}"))
            print(f"  [{i:>3}/{total}] {wid:<40}  HTTP {e.code} en {image_path}")
        except Exception as e:
            err += 1
            errors.append((wid, str(e)[:80]))
            print(f"  [{i:>3}/{total}] {wid:<40}  ERR: {e}")

    conn.commit()
    print()
    print(f"=== Resumen ===")
    print(f"  OK:     {ok}")
    print(f"  Errores: {err}")
    if errors:
        print(f"  Items con error:")
        for wid, msg in errors[:20]:
            print(f"    - {wid}: {msg}")
        if len(errors) > 20:
            print(f"    ... y {len(errors)-20} más")

    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
