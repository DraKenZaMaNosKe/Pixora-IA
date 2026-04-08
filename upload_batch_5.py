"""Upload 5 new wallpapers (atom + mai x2 + transformers x2) to Supabase + update catalog."""
import json
import sys
from pathlib import Path
import requests

SUPABASE_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6dXd2c21seWlnanRzZWFyeHltIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODY0ODcwOSwiZXhwIjoyMDc0MjI0NzA5fQ.xDs_HCkdqcEVJktzTdjGIXnG-V--j86jbkrUA4SjAOs"
BUCKET = "wallpaper-videos"
STAGING = Path(r"C:/Users/lalo/OneDrive/Escritorio/wallpapers/staging")

HEADERS = {"Authorization": f"Bearer {SERVICE_KEY}", "apikey": SERVICE_KEY}

ITEMS = [
    {
        "slug": "quantum_atom",
        "id": "quantum_atom_video",
        "name": "Quantum Atom",
        "description": "Cinematic quantum atom with electrons racing through 3D probability orbitals, leaving neon trails around a pulsing nucleus",
        "glowColor": "#00E5FF",
        "category": "SCIFI",
        "tags": ["atom", "quantum", "science", "physics", "neon", "scifi"],
        "sortOrder": 41,
    },
    {
        "slug": "mai_shiranui_win",
        "id": "mai_shiranui_win_video",
        "name": "Mai Shiranui — Win Pose",
        "description": "Mai Shiranui from King of Fighters in her victory pose with fan and fire effects, KOF HUD overlay",
        "glowColor": "#FF4500",
        "category": "GAMING",
        "tags": ["mai", "shiranui", "kof", "king of fighters", "gaming", "fighting", "anime"],
        "sortOrder": 42,
    },
    {
        "slug": "mai_shiranui_neon",
        "id": "mai_shiranui_neon_video",
        "name": "Mai Shiranui — Neon Halo",
        "description": "Mai Shiranui with a glowing neon halo, cherry blossoms and cyber arena background",
        "glowColor": "#00BFFF",
        "category": "GAMING",
        "tags": ["mai", "shiranui", "kof", "king of fighters", "gaming", "neon", "anime"],
        "sortOrder": 43,
    },
    {
        "slug": "bumblebee_war",
        "id": "bumblebee_war_video",
        "name": "Bumblebee — Last Stand",
        "description": "Bumblebee Autobot defending a destroyed city with cannon ready, fires and Autobot insignia in the background",
        "glowColor": "#FFD600",
        "category": "HEROES",
        "tags": ["bumblebee", "transformers", "autobot", "heroes", "robot", "scifi"],
        "sortOrder": 44,
    },
    {
        "slug": "decepticon_storm",
        "id": "decepticon_storm_video",
        "name": "Decepticon Storm",
        "description": "Massive Decepticon ship channeling a purple void with lightning bolts striking the ground below",
        "glowColor": "#9D00FF",
        "category": "HEROES",
        "tags": ["decepticon", "transformers", "robot", "scifi", "heroes", "villain"],
        "sortOrder": 45,
    },
]


def upload_file(local: Path, remote: str, ctype: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{remote}"
    h = {**HEADERS, "Content-Type": ctype, "x-upsert": "true"}
    data = local.read_bytes()
    last_err = None
    for attempt in range(5):
        try:
            r = requests.put(url, headers=h, data=data, timeout=180)
            if r.status_code in (200, 201):
                print(f"  OK   {remote} ({len(data)} bytes)")
                return True
            last_err = f"HTTP {r.status_code}: {r.text[:200]}"
        except Exception as e:
            last_err = str(e)[:200]
        import time
        time.sleep(2 * (attempt + 1))
    print(f"  FAIL {remote} after 5 retries: {last_err}")
    return False


def fetch_catalog() -> dict:
    url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/live_wallpaper_catalog.json"
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.json()


def push_catalog(data: dict):
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/live_wallpaper_catalog.json"
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
        upload_file(STAGING / "videos" / f"{slug}.mp4", f"videos/{slug}.mp4", "video/mp4")
        upload_file(STAGING / "videos" / f"{slug}_explore.mp4", f"videos/{slug}_explore.mp4", "video/mp4")
        upload_file(STAGING / "previews" / f"{slug}_preview.webp", f"previews/{slug}_preview.webp", "image/webp")
        for fr in sorted((STAGING / "frames" / slug).glob("frame_*.jpg")):
            upload_file(fr, f"frames/{slug}/{fr.name}", "image/jpeg")

    print("\n=== Updating catalog ===")
    catalog = fetch_catalog()
    existing = {w["id"] for w in catalog["wallpapers"]}
    for it in ITEMS:
        if it["id"] in existing:
            print(f"  SKIP {it['id']} already exists")
            continue
        slug = it["slug"]
        vsize = (STAGING / "videos" / f"{slug}.mp4").stat().st_size
        psize = (STAGING / "previews" / f"{slug}_preview.webp").stat().st_size
        catalog["wallpapers"].append({
            "id": it["id"],
            "name": it["name"],
            "description": it["description"],
            "videoFile": f"videos/{slug}.mp4",
            "previewFile": f"previews/{slug}_preview.webp",
            "videoSize": vsize,
            "previewSize": psize,
            "glowColor": it["glowColor"],
            "category": it["category"],
            "type": "video",
            "badge": "NEW",
            "sortOrder": it["sortOrder"],
            "tags": it["tags"],
            "downloadCount": 0,
            "createdAt": "2026-04-07T00:00:00Z",
            "exploreFile": f"videos/{slug}_explore.mp4",
            "frameCount": 36,
            "framesPath": f"frames/{slug}",
        })
        print(f"  ADD {it['id']}")

    catalog["version"] = catalog.get("version", 1) + 1
    push_catalog(catalog)
    print(f"\nCatalog now has {len(catalog['wallpapers'])} wallpapers (v{catalog['version']}).")


if __name__ == "__main__":
    main()
