"""Upload Pixora Volcano Dragon + Dusk Fortress wallpapers to Supabase.

Path MUST contain 'volcano_dragon' / 'dusk_fortress' — triggers their respective
renderers on the native side (PixoraWallpaperService.kt).
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

SRC_DIR = Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/claude")
OUT_DIR = Path(r"D:/Orbix/Pixora-IA/wallpapers_new")
FULL_W, FULL_H = 1080, 2340
PREV_W, PREV_H = 540, 1170

HEADERS = {"Authorization": f"Bearer {SERVICE_KEY}", "apikey": SERVICE_KEY}

WALLPAPERS = [
    {
        "src": SRC_DIR / "Gemini_Generated_Image_aehslqaehslqaehs.png",
        "id": "pixora_volcano_dragon",
        "name": "Volcano Dragon",
        "description": "Active volcano erupting molten lava under an ember-filled night sky — embers rising through the smoke toward the stars",
        "imageFile": "pixora_volcano_dragon.webp",
        "previewFile": "pixora_volcano_dragon_preview.webp",
        "glowColor": "#FF6A2A",
        "badge": "NEW",
        "sortOrder": 1,
        "category": "FANTASY",
        "featured": True,
        "tags": ["volcano", "dragon", "lava", "embers", "fantasy", "fire", "night", "animated"],
        "createdAt": "2026-04-23T00:00:00Z",
    },
    {
        "src": SRC_DIR / "Gemini_Generated_Image_bk0vv8bk0vv8bk0v.png",
        "id": "pixora_dusk_fortress",
        "name": "Dusk Fortress",
        "description": "Medieval castle perched on a dramatic cliff at dusk, torches flickering from arrow-slit windows, mist rising from the valley below",
        "imageFile": "pixora_dusk_fortress.webp",
        "previewFile": "pixora_dusk_fortress_preview.webp",
        "glowColor": "#C9A650",
        "badge": "NEW",
        "sortOrder": 2,
        "category": "FANTASY",
        "featured": True,
        "tags": ["castle", "medieval", "fortress", "dusk", "fantasy", "epic", "animated"],
        "createdAt": "2026-04-23T00:00:00Z",
    },
]


def prepare(item):
    print(f"\n[{item['id']}]")
    src = item["src"]
    if not src.exists():
        print(f"  FAIL: {src.name} not found")
        sys.exit(1)

    OUT_DIR.joinpath("static").mkdir(parents=True, exist_ok=True)
    OUT_DIR.joinpath("previews").mkdir(parents=True, exist_ok=True)

    img = Image.open(src).convert("RGB")
    print(f"  source: {img.size}")

    full_path = OUT_DIR / "static" / item["imageFile"]
    prev_path = OUT_DIR / "previews" / item["previewFile"]

    full = img.resize((FULL_W, FULL_H), Image.Resampling.LANCZOS)
    full.save(full_path, "WEBP", quality=85, method=6)
    print(f"  full:    {full_path.name} ({full_path.stat().st_size:,} bytes)")

    prev = full.resize((PREV_W, PREV_H), Image.Resampling.LANCZOS)
    prev.save(prev_path, "WEBP", quality=80, method=6)
    print(f"  preview: {prev_path.name} ({prev_path.stat().st_size:,} bytes)")

    return full_path, prev_path


def upload(local, remote, ctype):
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{remote}"
    h = {**HEADERS, "Content-Type": ctype, "x-upsert": "true"}
    data = local.read_bytes()
    for attempt in range(5):
        try:
            r = requests.put(url, headers=h, data=data, timeout=180)
            if r.status_code in (200, 201):
                print(f"  OK  {remote} ({len(data):,} bytes)")
                return True
            last = f"HTTP {r.status_code} {r.text[:200]}"
        except Exception as e:
            last = str(e)[:200]
        time.sleep(2 * (attempt + 1))
    print(f"  FAIL {remote}: {last}")
    return False


def fetch_catalog():
    url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{CATALOG}"
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.json()


def push_catalog(data):
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{CATALOG}"
    h = {**HEADERS, "Content-Type": "application/json", "x-upsert": "true"}
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    r = requests.put(url, headers=h, data=body, timeout=60)
    if r.status_code not in (200, 201):
        print(f"FAIL catalog: {r.status_code} {r.text[:500]}")
        sys.exit(1)
    print(f"OK catalog uploaded ({len(body):,} bytes)")


def verify(remote):
    url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{remote}"
    r = requests.head(url, timeout=15)
    ok = r.status_code == 200
    print(f"  {'OK  ' if ok else 'FAIL'} {url} -> HTTP {r.status_code}")
    return ok


def main():
    print("=== Preparing images ===")
    processed = []
    for item in WALLPAPERS:
        full_path, prev_path = prepare(item)
        processed.append((item, full_path, prev_path))

    print("\n=== Uploading to Supabase ===")
    for item, full_path, prev_path in processed:
        print(f"[{item['id']}]")
        upload(full_path, item["imageFile"], "image/webp")
        upload(prev_path, item["previewFile"], "image/webp")

    print("\n=== Verifying public URLs ===")
    for item, _, _ in processed:
        print(f"[{item['id']}]")
        verify(item["imageFile"])
        verify(item["previewFile"])

    print("\n=== Updating dynamic_catalog.json ===")
    catalog = fetch_catalog()
    existing_ids = {w["id"] for w in catalog["wallpapers"]}

    for item, full_path, prev_path in processed:
        if item["id"] in existing_ids:
            print(f"  SKIP {item['id']} already in catalog - refreshing metadata")
            catalog["wallpapers"] = [w for w in catalog["wallpapers"] if w["id"] != item["id"]]

        entry = {k: v for k, v in item.items() if k != "src"}
        entry["imageSize"] = full_path.stat().st_size
        entry["previewSize"] = prev_path.stat().st_size
        entry["downloadCount"] = 0
        catalog["wallpapers"].append(entry)

    catalog["version"] = catalog.get("version", 1) + 1
    push_catalog(catalog)
    print(f"\nCatalog now at v{catalog['version']} with {len(catalog['wallpapers'])} wallpapers.")


if __name__ == "__main__":
    main()
