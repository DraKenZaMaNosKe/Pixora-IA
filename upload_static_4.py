"""Upload 4 static wallpapers (Mai x2 + Transformers x2) to wallpaper-images bucket."""
import json
import sys
import time
from pathlib import Path
import requests

SUPABASE_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6dXd2c21seWlnanRzZWFyeHltIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODY0ODcwOSwiZXhwIjoyMDc0MjI0NzA5fQ.xDs_HCkdqcEVJktzTdjGIXnG-V--j86jbkrUA4SjAOs"
BUCKET = "wallpaper-images"
CATALOG = "dynamic_catalog.json"
STAGING = Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/staging/static")

HEADERS = {"Authorization": f"Bearer {SERVICE_KEY}", "apikey": SERVICE_KEY}

ITEMS = [
    {
        "slug": "mai_shiranui_win",
        "id": "mai_shiranui_win",
        "name": "Mai Shiranui — Win Pose",
        "description": "Mai Shiranui from King of Fighters in her victory pose with fan and fire effects",
        "glowColor": "#FF4500",
        "category": "GAMING",
        "tags": ["mai", "shiranui", "kof", "king of fighters", "gaming", "fighting", "anime"],
        "sortOrder": 147,
    },
    {
        "slug": "mai_shiranui_neon",
        "id": "mai_shiranui_neon",
        "name": "Mai Shiranui — Neon Halo",
        "description": "Mai Shiranui with a glowing neon halo, cherry blossoms and cyber arena background",
        "glowColor": "#00BFFF",
        "category": "GAMING",
        "tags": ["mai", "shiranui", "kof", "king of fighters", "gaming", "neon", "anime"],
        "sortOrder": 148,
    },
    {
        "slug": "bumblebee_war",
        "id": "bumblebee_war",
        "name": "Bumblebee — Last Stand",
        "description": "Bumblebee Autobot defending a destroyed city with cannon ready",
        "glowColor": "#FFD600",
        "category": "GAMING",
        "tags": ["bumblebee", "transformers", "autobot", "robot", "scifi"],
        "sortOrder": 149,
    },
    {
        "slug": "decepticon_storm",
        "id": "decepticon_storm",
        "name": "Decepticon Storm",
        "description": "Massive Decepticon ship channeling a purple void with lightning bolts",
        "glowColor": "#9D00FF",
        "category": "GAMING",
        "tags": ["decepticon", "transformers", "robot", "scifi", "villain"],
        "sortOrder": 150,
    },
]


def upload_file(local: Path, remote: str, ctype: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{remote}"
    h = {**HEADERS, "Content-Type": ctype, "x-upsert": "true"}
    data = local.read_bytes()
    last = None
    for attempt in range(5):
        try:
            r = requests.put(url, headers=h, data=data, timeout=180)
            if r.status_code in (200, 201):
                print(f"  OK   {remote} ({len(data)} bytes)")
                return True
            last = f"HTTP {r.status_code}"
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
    print(f"OK catalog uploaded ({len(body)} bytes)")


def main():
    for it in ITEMS:
        slug = it["slug"]
        print(f"=== {it['name']} ===")
        upload_file(STAGING / f"{slug}.webp", f"{slug}.webp", "image/webp")
        upload_file(STAGING / f"{slug}_preview.webp", f"{slug}_preview.webp", "image/webp")

    print("\n=== Updating dynamic_catalog.json ===")
    catalog = fetch_catalog()
    existing = {w["id"] for w in catalog["wallpapers"]}
    for it in ITEMS:
        if it["id"] in existing:
            print(f"  SKIP {it['id']} already exists")
            continue
        slug = it["slug"]
        isize = (STAGING / f"{slug}.webp").stat().st_size
        psize = (STAGING / f"{slug}_preview.webp").stat().st_size
        catalog["wallpapers"].append({
            "id": it["id"],
            "name": it["name"],
            "description": it["description"],
            "imageFile": f"{slug}.webp",
            "previewFile": f"{slug}_preview.webp",
            "imageSize": isize,
            "previewSize": psize,
            "glowColor": it["glowColor"],
            "badge": "NEW",
            "sortOrder": it["sortOrder"],
            "category": it["category"],
            "featured": True,
            "tags": it["tags"],
            "downloadCount": 0,
            "createdAt": "2026-04-07T00:00:00Z",
        })
        print(f"  ADD {it['id']}")

    catalog["version"] = catalog.get("version", 1) + 1
    push_catalog(catalog)
    print(f"\nCatalog now has {len(catalog['wallpapers'])} static wallpapers (v{catalog['version']}).")


if __name__ == "__main__":
    main()
