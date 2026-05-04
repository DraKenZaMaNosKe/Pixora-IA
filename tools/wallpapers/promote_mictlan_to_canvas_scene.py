"""
Move Mictlantecuhtli from the live_wallpaper_catalog (where it was a video
explore-mode wallpaper) to the catalog_index (where it lives alongside the
other canvas_scene wallpapers like Iah Egyptian, Goku Genkidama, Volcano
Dragon, etc.).

Steps:
  1. Rename + re-upload the background to follow the convention
     `pixora_<id>.webp` in the wallpaper-images bucket.
  2. Re-upload the existing preview to `pixora_<id>_preview.webp`.
  3. Move the scene spec from wallpaper-videos/scenes/ to wallpaper-scenes/.
  4. Add a new entry to catalog_index.json with type=canvas_scene.
  5. Bump catalog_index.json version.
  6. Remove the mictlantecuhtli entry from live_wallpaper_catalog.json so it
     doesn't appear duplicated in the LIVE tab.

Zero APK rebuild required — the parallaxWallpapersProvider auto-discovers
canvas_scene entries from the catalog_index.
"""
from __future__ import annotations
import json, re, sys, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
PROJECT = "vzuwvsmlyigjtsearxym"
SVC = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
                KEYS.read_text(encoding="utf-8")).group(1)


def get(bucket: str, key: str) -> bytes | None:
    url = f"https://{PROJECT}.supabase.co/storage/v1/object/public/{bucket}/{key}"
    try:
        return urllib.request.urlopen(url, timeout=60).read()
    except urllib.error.HTTPError as e:
        if e.code == 404: return None
        raise


def put(bucket: str, key: str, body: bytes, ctype: str):
    url = f"https://{PROJECT}.supabase.co/storage/v1/object/{bucket}/{key}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("Content-Type", ctype)
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.status


# ── 1. Background to wallpaper-images/pixora_mictlantecuhtli.webp ─────
print("1) Re-uploading background as pixora_mictlantecuhtli.webp...")
bg = get("wallpaper-images", "mictlan_background.webp")
if bg is None:
    raise SystemExit("Background not found at wallpaper-images/mictlan_background.webp")
put("wallpaper-images", "pixora_mictlantecuhtli.webp", bg, "image/webp")
print(f"   {len(bg)/1024:.0f} KB uploaded")

# ── 2. Preview to wallpaper-images/pixora_mictlantecuhtli_preview.webp ─
print("\n2) Re-uploading preview as pixora_mictlantecuhtli_preview.webp...")
preview = get("wallpaper-videos", "previews/mictlantecuhtli_preview_v2.webp")
if preview is None:
    raise SystemExit("Preview not found at wallpaper-videos/previews/mictlantecuhtli_preview_v2.webp")
put("wallpaper-images", "pixora_mictlantecuhtli_preview.webp", preview, "image/webp")
print(f"   {len(preview)/1024:.0f} KB uploaded")

# ── 3. Move spec from wallpaper-videos/scenes/ to wallpaper-scenes/ ──
print("\n3) Moving scene spec to wallpaper-scenes bucket...")
spec_bytes = get("wallpaper-videos", "scenes/mictlantecuhtli.json")
if spec_bytes is None:
    raise SystemExit("Spec not found at wallpaper-videos/scenes/mictlantecuhtli.json")
# Patch the spec's preview_url to point to the new convention path
spec = json.loads(spec_bytes)
spec["background"]["preview_url"] = (
    f"https://{PROJECT}.supabase.co/storage/v1/object/public/wallpaper-images/pixora_mictlantecuhtli_preview.webp"
)
spec["background"]["url"] = (
    f"https://{PROJECT}.supabase.co/storage/v1/object/public/wallpaper-images/pixora_mictlantecuhtli.webp"
)
spec_bytes = json.dumps(spec, ensure_ascii=False, indent=2).encode("utf-8")
put("wallpaper-scenes", "mictlantecuhtli.json", spec_bytes, "application/json")
print(f"   {len(spec_bytes)} bytes -> wallpaper-scenes/mictlantecuhtli.json")

# ── 4. Add entry to catalog_index.json ───────────────────────────────
print("\n4) Adding entry to catalog_index.json...")
idx_bytes = get("wallpaper-images", "catalog_index.json")
idx = json.loads(idx_bytes)
print(f"   Current version: {idx.get('version')}, items: {len(idx.get('items', []))}")

# Remove any old mictlantecuhtli entry if it exists (idempotent)
items = [it for it in idx.get("items", []) if it.get("id") != "mictlantecuhtli"]

new_entry = {
    "id": "mictlantecuhtli",
    "type": "canvas_scene",
    "schema": 1,
    "title": {
        "en": "Mictlantecuhtli",
        "es": "Mictlantecuhtli · Señor del Mictlán"
    },
    "preview_url": f"https://{PROJECT}.supabase.co/storage/v1/object/public/wallpaper-images/pixora_mictlantecuhtli_preview.webp",
    "tags": ["mythology","aztec","mexica","underworld","death","culture","live","animated","3d","parallax"],
    "category": "culture",
    "featured": True,
    "spec_url": f"https://{PROJECT}.supabase.co/storage/v1/object/public/wallpaper-scenes/mictlantecuhtli.json"
}
items.append(new_entry)
idx["items"] = items
idx["version"] = (idx.get("version", 25) or 25) + 1
print(f"   New version: {idx['version']}, items: {len(items)} (entry added)")

idx_body = json.dumps(idx, ensure_ascii=False, indent=2).encode("utf-8")
put("wallpaper-images", "catalog_index.json", idx_body, "application/json")
print(f"   Catalog index re-uploaded ({len(idx_body)} bytes)")

# ── 5. Remove from live_wallpaper_catalog ─────────────────────────────
print("\n5) Removing mictlantecuhtli from live_wallpaper_catalog.json...")
lc_bytes = get("wallpaper-videos", "live_wallpaper_catalog.json")
lc = json.loads(lc_bytes)
before = len(lc.get("wallpapers", []))
lc["wallpapers"] = [w for w in lc.get("wallpapers", []) if w.get("id") != "mictlantecuhtli"]
after = len(lc["wallpapers"])
print(f"   Removed {before - after} entry(ies); live catalog now has {after} wallpapers")
lc_body = json.dumps(lc, ensure_ascii=False, indent=2).encode("utf-8")
put("wallpaper-videos", "live_wallpaper_catalog.json", lc_body, "application/json")
print(f"   Live catalog re-uploaded ({len(lc_body)} bytes)")

print()
print("==============================================================")
print("DONE. Mictlantecuhtli is now a canvas_scene wallpaper alongside")
print("Iah Egyptian, Goku Genkidama, Volcano Dragon, etc.")
print()
print("Next:")
print("  - User clears Pixora cache (force-stop)")
print("  - Opens Pixora -> 3D / Parallax wallpapers tab")
print("  - Sees Mictlantecuhtli with native particles + animated sprite")
print("==============================================================")
