"""
Convert Mictlantecuhtli from broken raw-MP4 mode to working Explore (Canvas)
mode by uploading the 61 pre-extracted frames and updating the catalog
entry to add frameCount + framesPath + exploreOnly.

This matches the pattern used by all other 57 video wallpapers in Pixora's
catalog. The MediaPlayer code path has Pitfall A (Surface conflict) on
Samsung One UI; Explore mode bypasses MediaPlayer entirely.
"""
from __future__ import annotations
import json, re, sys, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
PROJECT_REF = "vzuwvsmlyigjtsearxym"
BUCKET = "wallpaper-videos"
FRAMES_DIR = Path(r"C:/Users/lalo/AppData/Local/Temp/mictlan_frames")
REMOTE_FRAMES_PREFIX = "frames/mictlantecuhtli_v2"
CATALOG_KEY = "live_wallpaper_catalog.json"


def get_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", text)
    if not m:
        raise SystemExit("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


SVC = get_service_key()


def upload(key: str, body: bytes, content_type: str) -> None:
    url = f"https://{PROJECT_REF}.supabase.co/storage/v1/object/{BUCKET}/{key}"
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("Content-Type", content_type)
    req.add_header("x-upsert", "true")
    try:
        urllib.request.urlopen(req, timeout=60)
    except urllib.error.HTTPError as e:
        if e.code in (400, 409):
            req2 = urllib.request.Request(url, data=body, method="PUT")
            req2.add_header("Authorization", f"Bearer {SVC}")
            req2.add_header("Content-Type", content_type)
            req2.add_header("x-upsert", "true")
            urllib.request.urlopen(req2, timeout=60)
        else:
            raise


def download_catalog() -> dict:
    url = f"https://{PROJECT_REF}.supabase.co/storage/v1/object/public/{BUCKET}/{CATALOG_KEY}"
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.loads(r.read())


def main():
    frames = sorted(FRAMES_DIR.glob("frame_*.jpg"))
    if not frames:
        raise SystemExit(f"No frames in {FRAMES_DIR}")
    print(f"Found {len(frames)} frames in {FRAMES_DIR}")

    print("Uploading frames...")
    for i, f in enumerate(frames, 1):
        key = f"{REMOTE_FRAMES_PREFIX}/{f.name}"
        upload(key, f.read_bytes(), "image/jpeg")
        if i % 10 == 0 or i == len(frames):
            print(f"  {i}/{len(frames)} uploaded")

    print("Patching catalog...")
    cat = download_catalog()
    found = False
    for w in cat.get("wallpapers", []):
        if w.get("id") == "mictlantecuhtli":
            w["frameCount"] = len(frames)
            w["framesPath"] = REMOTE_FRAMES_PREFIX
            w["exploreOnly"] = True
            w["exploreFile"] = w.get("videoFile")  # required by model.exploreUrl fallback
            found = True
            print(f"  patched mictlantecuhtli: frameCount={len(frames)} framesPath={REMOTE_FRAMES_PREFIX}")
            break
    if not found:
        raise SystemExit("mictlantecuhtli entry not found in catalog")

    cat["version"] = (cat.get("version") or 0) + 1 if isinstance(cat.get("version"), int) else cat.get("version")
    body = json.dumps(cat, ensure_ascii=False, indent=2).encode("utf-8")
    upload(CATALOG_KEY, body, "application/json")
    print(f"  catalog re-uploaded ({len(body)} bytes)")
    print()
    print("Done. User must clear app cache or wait for 6h cache TTL.")


if __name__ == "__main__":
    main()
