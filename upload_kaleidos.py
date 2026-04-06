"""Upload kaleidoscope wallpapers to Supabase Storage and update catalog."""
import json
import os
import sys
from pathlib import Path
import requests

SUPABASE_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6dXd2c21seWlnanRzZWFyeHltIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODY0ODcwOSwiZXhwIjoyMDc0MjI0NzA5fQ.xDs_HCkdqcEVJktzTdjGIXnG-V--j86jbkrUA4SjAOs"
BUCKET = "wallpaper-videos"
STAGING = Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/caleidoscopio/staging")

HEADERS_BIN = {
    "Authorization": f"Bearer {SERVICE_KEY}",
    "apikey": SERVICE_KEY,
}

KALEIDOS = [
    {
        "id": "cosmic_lotus_video",
        "name": "Cosmic Lotus",
        "description": "Galactic mandala lotus blooming in deep space with radiant cosmic rays",
        "glowColor": "#9C6BFF",
        "tags": ["kaleidoscope", "mandala", "cosmic", "galaxy", "chill", "meditation"],
        "sortOrder": 37,
    },
    {
        "id": "peacock_bloom_video",
        "name": "Peacock Bloom",
        "description": "Iridescent peacock feathers woven with floral mandala on midnight green",
        "glowColor": "#00C89C",
        "tags": ["kaleidoscope", "mandala", "peacock", "floral", "nature", "chill"],
        "sortOrder": 38,
    },
    {
        "id": "neon_star_forge_video",
        "name": "Neon Star Forge",
        "description": "Electric neon kaleidoscope with a pulsing star core and prismatic flares",
        "glowColor": "#FF2EB5",
        "tags": ["kaleidoscope", "mandala", "neon", "prism", "electric", "chill"],
        "sortOrder": 39,
    },
    {
        "id": "solar_hive_video",
        "name": "Solar Hive",
        "description": "Golden honeycomb kaleidoscope with a blazing sun at its heart",
        "glowColor": "#FFB84D",
        "tags": ["kaleidoscope", "mandala", "solar", "honeycomb", "warm", "chill"],
        "sortOrder": 40,
    },
]


def upload_file(local_path: Path, remote_path: str, content_type: str):
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{remote_path}"
    headers = {**HEADERS_BIN, "Content-Type": content_type, "x-upsert": "true"}
    with open(local_path, "rb") as f:
        r = requests.put(url, headers=headers, data=f.read(), timeout=120)
    if r.status_code not in (200, 201):
        print(f"  FAIL {remote_path}: {r.status_code} {r.text[:200]}")
        return False
    print(f"  OK   {remote_path} ({local_path.stat().st_size} bytes)")
    return True


def download_catalog() -> dict:
    url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/live_wallpaper_catalog.json"
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.json()


def upload_catalog(data: dict):
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/live_wallpaper_catalog.json"
    headers = {**HEADERS_BIN, "Content-Type": "application/json", "x-upsert": "true"}
    body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
    r = requests.put(url, headers=headers, data=body, timeout=60)
    if r.status_code not in (200, 201):
        print(f"FAIL catalog upload: {r.status_code} {r.text[:500]}")
        sys.exit(1)
    print(f"OK catalog uploaded ({len(body)} bytes)")


def main():
    slug_map = {
        "cosmic_lotus_video": "cosmic_lotus",
        "peacock_bloom_video": "peacock_bloom",
        "neon_star_forge_video": "neon_star_forge",
        "solar_hive_video": "solar_hive",
    }

    # Upload files
    for entry in KALEIDOS:
        slug = slug_map[entry["id"]]
        print(f"=== {entry['name']} ===")

        # Video auto-play
        upload_file(
            STAGING / "videos" / f"{slug}.mp4",
            f"videos/{slug}.mp4",
            "video/mp4",
        )
        # Video explore
        upload_file(
            STAGING / "videos" / f"{slug}_explore.mp4",
            f"videos/{slug}_explore.mp4",
            "video/mp4",
        )
        # Preview
        upload_file(
            STAGING / "previews" / f"{slug}_preview.webp",
            f"previews/{slug}_preview.webp",
            "image/webp",
        )
        # Frames (36 per video)
        frames_dir = STAGING / "frames" / slug
        for frame in sorted(frames_dir.glob("frame_*.jpg")):
            upload_file(
                frame,
                f"frames/{slug}/{frame.name}",
                "image/jpeg",
            )

    # Download + update catalog
    print("\n=== Updating catalog ===")
    catalog = download_catalog()
    existing_ids = {w["id"] for w in catalog["wallpapers"]}

    for entry in KALEIDOS:
        if entry["id"] in existing_ids:
            print(f"  SKIP {entry['id']} already exists")
            continue
        slug = slug_map[entry["id"]]
        video_size = (STAGING / "videos" / f"{slug}.mp4").stat().st_size
        preview_size = (STAGING / "previews" / f"{slug}_preview.webp").stat().st_size
        new_item = {
            "id": entry["id"],
            "name": entry["name"],
            "description": entry["description"],
            "videoFile": f"videos/{slug}.mp4",
            "previewFile": f"previews/{slug}_preview.webp",
            "videoSize": video_size,
            "previewSize": preview_size,
            "glowColor": entry["glowColor"],
            "category": "CHILL",
            "type": "video",
            "badge": "NEW",
            "sortOrder": entry["sortOrder"],
            "tags": entry["tags"],
            "downloadCount": 0,
            "createdAt": "2026-04-06T00:00:00Z",
            "exploreFile": f"videos/{slug}_explore.mp4",
            "frameCount": 36,
            "framesPath": f"frames/{slug}",
        }
        catalog["wallpapers"].append(new_item)
        print(f"  ADD {entry['id']}")

    catalog["version"] = catalog.get("version", 1) + 1
    upload_catalog(catalog)
    print(f"\nCatalog now has {len(catalog['wallpapers'])} wallpapers (version {catalog['version']}).")


if __name__ == "__main__":
    main()
