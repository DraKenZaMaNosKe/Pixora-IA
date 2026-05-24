"""
One-shot: sube los 4 assets de Bulma a Supabase Storage y actualiza catálogos.

  1. Sube 3 WebP + 3 previews a wallpaper-images
  2. Sube videos/bulma_live.mp4 + previews/bulma_live_preview.webp a wallpaper-videos
  3. GET dynamic_catalog.json, append 3 entries (static + 2 panoramic), PUT back
  4. GET live_wallpaper_catalog.json, append 1 entry (live), PUT back
"""
from __future__ import annotations
import sys, re, json, urllib.request
from pathlib import Path
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8")
SERVICE_KEY = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", KEYS).group(1)

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
SRC = Path(r"D:/Orbix/Pixora-IA/tools/wallpapers/_bulma_processed")
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def upload(local_path: Path, bucket: str, remote: str, content_type: str) -> int:
    body = local_path.read_bytes()
    url = f"{PROJECT}/storage/v1/object/{bucket}/{remote}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", content_type)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=60) as r:
        print(f"  PUT {bucket}/{remote}  →  {r.status} ({len(body):,} bytes)")
    return len(body)


def get_catalog(bucket: str, file: str) -> dict:
    url = f"{PROJECT}/storage/v1/object/public/{bucket}/{file}"
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def put_catalog(bucket: str, file: str, data: dict):
    body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
    url = f"{PROJECT}/storage/v1/object/{bucket}/{file}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SERVICE_KEY}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"  PUT {bucket}/{file}  →  {r.status} ({len(body):,} bytes)")


def upsert_entry(items: list, new_entry: dict) -> None:
    """Replace by id if exists, else append."""
    idx = next((i for i, w in enumerate(items) if w.get("id") == new_entry["id"]), -1)
    if idx >= 0:
        print(f"    ⚠️  {new_entry['id']} already exists (idx {idx}) — replacing")
        items[idx] = new_entry
    else:
        items.append(new_entry)
        print(f"    ✅ {new_entry['id']} appended (now {len(items)} total)")


# ─── 1. Upload images to wallpaper-images ──────────────────────
print("\n[1/4] Uploading images to wallpaper-images bucket…")
static_size = upload(SRC / "bulma_sexy_estatico.webp", "wallpaper-images", "bulma_portrait.webp", "image/webp")
static_prev = upload(SRC / "bulma_sexy_estatico_preview.webp", "wallpaper-images", "bulma_portrait_preview.webp", "image/webp")
pano0_size = upload(SRC / "bulma_sexy_panoramico_00.webp", "wallpaper-images", "bulma_bedroom_pano.webp", "image/webp")
pano0_prev = upload(SRC / "bulma_sexy_panoramico_00_preview.webp", "wallpaper-images", "bulma_bedroom_pano_preview.webp", "image/webp")
pano1_size = upload(SRC / "bulma_sexy_panoramico_01.webp", "wallpaper-images", "bulma_vanity_pano.webp", "image/webp")
pano1_prev = upload(SRC / "bulma_sexy_panoramico_01_preview.webp", "wallpaper-images", "bulma_vanity_pano_preview.webp", "image/webp")

# ─── 2. Upload live wallpaper to wallpaper-videos ──────────────
print("\n[2/4] Uploading live wallpaper to wallpaper-videos bucket…")
video_size = upload(SRC / "bulma_sexy_live.mp4", "wallpaper-videos", "videos/bulma_live.mp4", "video/mp4")
video_prev = upload(SRC / "bulma_sexy_live_preview.webp", "wallpaper-videos", "previews/bulma_live_preview.webp", "image/webp")

# ─── 3. Update dynamic_catalog.json (static + panoramics) ──────
print("\n[3/4] Updating dynamic_catalog.json…")
dyn = get_catalog("wallpaper-images", "dynamic_catalog.json")
print(f"  Current items: {len(dyn['wallpapers'])}")

# sortOrder: use 1 for new featured items (consistent with prod panoramics we measured)
upsert_entry(dyn["wallpapers"], {
    "id": "bulma_portrait",
    "type": "image",
    "name": "Bulma - Cyan Hair Portrait",
    "description": "Bulma, la genio científica de cabello turquesa de Dragon Ball",
    "imageFile": "bulma_portrait.webp",
    "previewFile": "bulma_portrait_preview.webp",
    "imageSize": static_size,
    "previewSize": static_prev,
    "glowColor": "#00E5FF",
    "badge": "NEW",
    "sortOrder": 1,
    "category": "ANIME",
    "featured": True,
    "tags": ["bulma", "dragon_ball", "anime", "girl", "blue_hair", "scifi", "portrait"],
    "downloadCount": 0,
    "createdAt": NOW,
})

upsert_entry(dyn["wallpapers"], {
    "id": "bulma_bedroom_pano",
    "type": "image",
    "name": "Bulma - Holographic Bedroom",
    "description": "Ultra-wide panoramic de la habitación futurista de Bulma con pantallas holográficas al atardecer",
    "imageFile": "bulma_bedroom_pano.webp",
    "previewFile": "bulma_bedroom_pano_preview.webp",
    "imageSize": pano0_size,
    "previewSize": pano0_prev,
    "glowColor": "#FF80AB",
    "badge": "NEW",
    "sortOrder": 1,
    "category": "PANORAMIC",
    "featured": True,
    "tags": ["bulma", "dragon_ball", "anime", "panoramic", "scifi", "bedroom", "holographic"],
    "downloadCount": 0,
    "createdAt": NOW,
})

upsert_entry(dyn["wallpapers"], {
    "id": "bulma_vanity_pano",
    "type": "image",
    "name": "Bulma - Rose Gold Vanity",
    "description": "Ultra-wide panoramic de Bulma en su tocador glamuroso de oro rosa con orquídeas",
    "imageFile": "bulma_vanity_pano.webp",
    "previewFile": "bulma_vanity_pano_preview.webp",
    "imageSize": pano1_size,
    "previewSize": pano1_prev,
    "glowColor": "#FFB6C1",
    "badge": "NEW",
    "sortOrder": 1,
    "category": "PANORAMIC",
    "featured": True,
    "tags": ["bulma", "dragon_ball", "anime", "panoramic", "vanity", "glamour", "pink"],
    "downloadCount": 0,
    "createdAt": NOW,
})

dyn["lastUpdated"] = NOW
put_catalog("wallpaper-images", "dynamic_catalog.json", dyn)

# ─── 4. Update live_wallpaper_catalog.json (video) ─────────────
print("\n[4/4] Updating live_wallpaper_catalog.json…")
live = get_catalog("wallpaper-videos", "live_wallpaper_catalog.json")
print(f"  Current items: {len(live['wallpapers'])}")

max_sort_live = max((w.get("sortOrder", 0) for w in live["wallpapers"]), default=0)
upsert_entry(live["wallpapers"], {
    "id": "bulma_live",
    "type": "video",
    "name": "Bulma - Cyan Genius Live",
    "description": "Bulma, la genio científica animada de Dragon Ball",
    "videoFile": "videos/bulma_live.mp4",
    "previewFile": "previews/bulma_live_preview.webp",
    "videoSize": video_size,
    "previewSize": video_prev,
    "glowColor": "#00E5FF",
    "category": "ANIME",
    "badge": "NEW",
    "sortOrder": max_sort_live + 1,
    "tags": ["bulma", "dragon_ball", "anime", "girl", "blue_hair", "live", "scifi"],
    "downloadCount": 0,
    "createdAt": NOW,
})

live["lastUpdated"] = NOW
put_catalog("wallpaper-videos", "live_wallpaper_catalog.json", live)

# ─── 5. Final verification ─────────────────────────────────────
print("\n" + "=" * 60)
print("✅ UPLOAD COMPLETE — verifying public URLs return 200…")
print("=" * 60)
import urllib.error
test_urls = [
    f"{PROJECT}/storage/v1/object/public/wallpaper-images/bulma_portrait.webp",
    f"{PROJECT}/storage/v1/object/public/wallpaper-images/bulma_bedroom_pano.webp",
    f"{PROJECT}/storage/v1/object/public/wallpaper-images/bulma_vanity_pano.webp",
    f"{PROJECT}/storage/v1/object/public/wallpaper-videos/videos/bulma_live.mp4",
]
for url in test_urls:
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=10) as r:
            print(f"  ✅ {r.status}  {url.split('/')[-1]}")
    except urllib.error.HTTPError as e:
        print(f"  ❌ {e.code}  {url.split('/')[-1]}")

print("\nTodos los assets subidos y catálogos actualizados.")
print("Próximo paso opcional: disparar FCM catalog_invalidate para refresh inmediato en devices.")
