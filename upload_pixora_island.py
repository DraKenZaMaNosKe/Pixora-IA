"""Upload pixora_island static wallpaper (sunset tropical beach) to Supabase.

Path MUST contain 'pixora_island' — triggers PixoraFriendsRenderer on the
native side (PixoraWallpaperService.kt, same pattern as aquarium/jellyfish).
The mascot sprite frames are bundled in APK assets under pixora_island/.
"""
import json
import sys
import time
from pathlib import Path
import requests
from PIL import Image

SUPABASE_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6dXd2c21seWlnanRzZWFyeHltIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODY0ODcwOSwiZXhwIjoyMDc0MjI0NzA5fQ.xDs_HCkdqcEVJktzTdjGIXnG-V--j86jbkrUA4SjAOs"
BUCKET = "wallpaper-images"
CATALOG = "dynamic_catalog.json"

SRC_BG = Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/adventure_island/Gemini_Generated_Image_innpmfinnpmfinnp.png")
OUT_DIR = Path(r"D:/Orbix/Pixora-IA/wallpapers_new")
FULL_PATH = OUT_DIR / "static" / "pixora_island.webp"
PREV_PATH = OUT_DIR / "previews" / "pixora_island_preview.webp"

FULL_W, FULL_H = 1080, 2340
PREV_W, PREV_H = 540, 1170

HEADERS = {"Authorization": f"Bearer {SERVICE_KEY}", "apikey": SERVICE_KEY}

ITEM = {
    "id": "pixora_island",
    "name": "Pixora Island",
    "description": "Chibi mascot and purple dragon living on a tropical sunset beach — they wake, walk, snack on diamonds and sleep following the time of day",
    "imageFile": "pixora_island.webp",
    "previewFile": "pixora_island_preview.webp",
    "glowColor": "#FFB26B",
    "badge": "NEW",
    "sortOrder": 0,
    "category": "FANTASY",
    "featured": True,
    "tags": ["mascot", "chibi", "dragon", "beach", "tropical", "sunset", "animated", "day_cycle"],
    "downloadCount": 0,
    "createdAt": "2026-04-21T00:00:00Z",
}


def prepare_images():
    OUT_DIR.joinpath("static").mkdir(parents=True, exist_ok=True)
    OUT_DIR.joinpath("previews").mkdir(parents=True, exist_ok=True)

    img = Image.open(SRC_BG).convert("RGB")
    print(f"Source: {img.size}")

    full = img.resize((FULL_W, FULL_H), Image.Resampling.LANCZOS)
    full.save(FULL_PATH, "WEBP", quality=85, method=6)
    print(f"  full:    {FULL_PATH.name} {full.size} ({FULL_PATH.stat().st_size:,} bytes)")

    prev = full.resize((PREV_W, PREV_H), Image.Resampling.LANCZOS)
    prev.save(PREV_PATH, "WEBP", quality=80, method=6)
    print(f"  preview: {PREV_PATH.name} {prev.size} ({PREV_PATH.stat().st_size:,} bytes)")


def upload_file(local: Path, remote: str, ctype: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{remote}"
    h = {**HEADERS, "Content-Type": ctype, "x-upsert": "true"}
    data = local.read_bytes()
    for attempt in range(5):
        try:
            r = requests.put(url, headers=h, data=data, timeout=180)
            if r.status_code in (200, 201):
                print(f"  OK   {remote} ({len(data):,} bytes)")
                return True
            last = f"HTTP {r.status_code} {r.text[:200]}"
        except Exception as e:
            last = str(e)[:200]
        time.sleep(2 * (attempt + 1))
    print(f"  FAIL {remote}: {last}")
    return False


def fetch_catalog() -> dict:
    url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{CATALOG}"
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.json()


def push_catalog(data: dict):
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{CATALOG}"
    h = {**HEADERS, "Content-Type": "application/json", "x-upsert": "true"}
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    r = requests.put(url, headers=h, data=body, timeout=60)
    if r.status_code not in (200, 201):
        print(f"FAIL catalog: {r.status_code} {r.text[:500]}")
        sys.exit(1)
    print(f"OK catalog uploaded ({len(body):,} bytes)")


def verify_public_url(remote: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{remote}"
    r = requests.head(url, timeout=15)
    ok = r.status_code == 200
    print(f"  {'OK  ' if ok else 'FAIL'} {url} -> HTTP {r.status_code}")
    return ok


def main():
    print("=== Preparing pixora_island images ===")
    if not SRC_BG.exists():
        print(f"Missing source: {SRC_BG}")
        sys.exit(1)
    prepare_images()

    print("\n=== Uploading to Supabase ===")
    upload_file(FULL_PATH, ITEM["imageFile"], "image/webp")
    upload_file(PREV_PATH, ITEM["previewFile"], "image/webp")

    print("\n=== Verifying public URLs ===")
    verify_public_url(ITEM["imageFile"])
    verify_public_url(ITEM["previewFile"])

    print("\n=== Updating dynamic_catalog.json ===")
    catalog = fetch_catalog()
    existing = {w["id"] for w in catalog["wallpapers"]}
    if ITEM["id"] in existing:
        print(f"  SKIP {ITEM['id']} already in catalog - will refresh metadata")
        catalog["wallpapers"] = [w for w in catalog["wallpapers"] if w["id"] != ITEM["id"]]

    entry = {
        **ITEM,
        "imageSize": FULL_PATH.stat().st_size,
        "previewSize": PREV_PATH.stat().st_size,
    }
    catalog["wallpapers"].append(entry)
    catalog["version"] = catalog.get("version", 1) + 1
    push_catalog(catalog)
    print(f"\nCatalog now at v{catalog['version']} with {len(catalog['wallpapers'])} wallpapers.")


if __name__ == "__main__":
    main()
