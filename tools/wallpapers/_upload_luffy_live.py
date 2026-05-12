"""
One-shot: subir Monkey D. Luffy como LIVE wallpaper.

  1. Sube videos/monkey_d_luffy.mp4 a wallpaper-videos
  2. Sube previews/monkey_d_luffy_preview.webp a wallpaper-videos
  3. GET live_wallpaper_catalog.json, append entry, PUT back
"""
from __future__ import annotations
import sys, re, json, urllib.request
from pathlib import Path
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
SERVICE_KEY = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", KEYS).group(1)

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-videos"
SRC = Path(r"C:/Users/lalo/OneDrive/Escritorio/Pixora_Content_Inbox/tmp")

WALLPAPER_ID = "monkey_d_luffy"
VIDEO_FILE = "videos/monkey_d_luffy.mp4"
PREV_FILE = "previews/monkey_d_luffy_preview.webp"

video_path = SRC / "MonkeyD.mp4"
prev_path = SRC / "luffy_preview.webp"


def upload(local_path: Path, remote: str, content_type: str) -> int:
    """Returns the uploaded file size in bytes."""
    body = local_path.read_bytes()
    url = f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", content_type)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=60) as r:
        print(f"  PUT {remote}  →  {r.status} ({len(body):,} bytes)")
    return len(body)


print("\n[1/3] Uploading video…")
video_size = upload(video_path, VIDEO_FILE, "video/mp4")

print("\n[2/3] Uploading preview…")
prev_size = upload(prev_path, PREV_FILE, "image/webp")

print("\n[3/3] Appending entry to live_wallpaper_catalog.json…")
catalog_url_public = f"{PROJECT}/storage/v1/object/public/{BUCKET}/live_wallpaper_catalog.json"
with urllib.request.urlopen(catalog_url_public, timeout=15) as r:
    catalog = json.loads(r.read().decode("utf-8"))

# Compute next sortOrder
max_sort = max((w.get("sortOrder", 0) for w in catalog["wallpapers"]), default=0)
new_sort = max_sort + 1

entry = {
    "id": WALLPAPER_ID,
    "name": "Monkey D. Luffy",
    "description": "El rey de los piratas con armadura cósmica - One Piece",
    "videoFile": VIDEO_FILE,
    "previewFile": PREV_FILE,
    "videoSize": video_size,
    "previewSize": prev_size,
    "glowColor": "#FF4500",
    "category": "ANIME",
    "type": "video",
    "badge": "NEW",
    "sortOrder": new_sort,
    "tags": ["luffy", "one-piece", "anime", "pirate", "king", "strawhat"],
    "downloadCount": 0,
    "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}

# Avoid duplicates: replace if id exists, else append
existing_idx = next((i for i, w in enumerate(catalog["wallpapers"]) if w["id"] == WALLPAPER_ID), -1)
if existing_idx >= 0:
    print(f"  WARN: {WALLPAPER_ID} already in catalog (idx {existing_idx}) — replacing")
    catalog["wallpapers"][existing_idx] = entry
else:
    catalog["wallpapers"].append(entry)

catalog["lastUpdated"] = entry["createdAt"]

# Upload catalog
payload = json.dumps(catalog, indent=2, ensure_ascii=False).encode("utf-8")
url = f"{PROJECT}/storage/v1/object/{BUCKET}/live_wallpaper_catalog.json"
req = urllib.request.Request(url, data=payload, method="PUT")
req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
req.add_header("Content-Type", "application/json")
req.add_header("x-upsert", "true")
with urllib.request.urlopen(req, timeout=20) as r:
    print(f"  PUT catalog  →  {r.status}")

print(f"\n✅ Monkey D. Luffy publicado")
print(f"   sortOrder: {new_sort}")
print(f"   total LIVE wallpapers ahora: {len(catalog['wallpapers'])}")
