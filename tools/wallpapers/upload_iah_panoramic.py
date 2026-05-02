"""
Uploads the Iah Egyptian panoramic .webp to Supabase Storage and switches
the catalog entry from type=canvas_scene -> type=panoramic so it goes
through the static wallpaper code path (Samsung's ImageWallpaper) instead
of our PixoraWallpaperService Live engine.
"""
from __future__ import annotations
import json, re, sys, urllib.request
from pathlib import Path

# Force UTF-8 stdout for Windows cp1252 console
sys.stdout.reconfigure(encoding="utf-8")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
PROJECT_REF = "vzuwvsmlyigjtsearxym"
BUCKET = "wallpaper-images"
LOCAL_FILE = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian/panoramic/iah_egyptian_giza_panoramic.webp")
REMOTE_NAME = "pixora_iah_egyptian_giza_panoramic.webp"  # what it'll be called in Storage
WALLPAPER_ID = "iah_egyptian_giza"


def get_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", text)
    if not m:
        raise SystemExit("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


def upload_to_storage(key: str, body: bytes) -> str:
    """Upsert object into wallpaper-images bucket. Returns public URL."""
    url = f"https://{PROJECT_REF}.supabase.co/storage/v1/object/{BUCKET}/{key}"
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("Content-Type", "image/webp")
    req.add_header("x-upsert", "true")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            print(f"  upload status: {r.status}")
    except urllib.error.HTTPError as e:
        # 409 = exists, retry with PUT (overwrite)
        if e.code in (400, 409):
            req2 = urllib.request.Request(url, data=body, method="PUT")
            req2.add_header("Authorization", f"Bearer {SVC}")
            req2.add_header("Content-Type", "image/webp")
            req2.add_header("x-upsert", "true")
            with urllib.request.urlopen(req2, timeout=60) as r:
                print(f"  upload (PUT) status: {r.status}")
        else:
            raise
    return f"https://{PROJECT_REF}.supabase.co/storage/v1/object/public/{BUCKET}/{key}"


def update_catalog_row(public_url: str):
    """PATCH the wallpapers row to type=panoramic with the new URL."""
    api = f"https://{PROJECT_REF}.supabase.co/rest/v1/wallpapers?id=eq.{WALLPAPER_ID}"
    payload = json.dumps({
        "type": "panoramic",
        "url": public_url,
    }).encode("utf-8")
    req = urllib.request.Request(api, data=payload, method="PATCH")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("apikey", SVC)
    req.add_header("Content-Type", "application/json")
    req.add_header("Prefer", "return=representation")
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read().decode("utf-8")
        print(f"  patch status: {r.status}")
        print(f"  result: {body[:300]}")


if __name__ == "__main__":
    SVC = get_service_key()

    print(f"Reading {LOCAL_FILE.name} ({LOCAL_FILE.stat().st_size:,} bytes)")
    body = LOCAL_FILE.read_bytes()

    print(f"Uploading to {BUCKET}/{REMOTE_NAME}")
    url = upload_to_storage(REMOTE_NAME, body)
    print(f"  public URL: {url}")

    print(f"Updating catalog row for {WALLPAPER_ID}")
    update_catalog_row(url)

    print("\nDONE — Iah Egyptian is now a panoramic static wallpaper.")
    print("Open Pixora -> Wallpapers tab -> reapply Iah Egyptian Giza")
    print("It should now scroll natively on home like Akuma.")
