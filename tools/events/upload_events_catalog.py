"""
Upload events_catalog.json to Supabase Storage. Same pattern as the other
catalogs (catalog_index, live_wallpaper_catalog, etc.) — single JSON file,
6h client cache, edit + re-upload to update.

Schema per event:
  id              : str  (stable, e.g. "dia_muertos_2026")
  name            : str  (display name)
  description     : str  (short paragraph)
  icon            : str  (emoji, single char)
  theme_color     : str  (#RRGGBB — primary)
  theme_color_dark: str  (#RRGGBB — gradient bottom)
  starts_at       : ISO8601 timestamp
  ends_at         : ISO8601 timestamp
  is_pro_only     : bool (true = locked behind subscription)
  wallpaper_ids   : list[str] (refs into wallpapers / live_wallpaper catalogs)
  wallpaper_count : int (display number even when wallpaper_ids is empty)
  tags            : list[str]
  banner_url      : str | null  (custom hero image; null = use theme gradient)
  memoria_url     : str | null  (post-event memory image for past events)
"""
from __future__ import annotations
import json, re, sys, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
SVC = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
                KEYS.read_text(encoding="utf-8")).group(1)
PROJECT = "vzuwvsmlyigjtsearxym"
LOCAL = Path(r"D:/Orbix/Pixora-IA/tools/events/events_catalog.json")

# Stored in wallpaper-images bucket so it's served from the same CDN as
# the other catalogs (consistent caching + simpler bucket policy).
KEY = "events_catalog.json"
BUCKET = "wallpaper-images"


def main():
    body = LOCAL.read_bytes()
    # Validate JSON before upload
    catalog = json.loads(body)
    print(f"Catalog version: {catalog['version']}")
    print(f"Events: {len(catalog['events'])}")
    for e in catalog["events"]:
        print(f"  {e['icon']} {e['id']:30s} {e['starts_at'][:10]} — "
              f"{e['ends_at'][:10]}  ({e['wallpaper_count']} wallpapers)")

    url = f"https://{PROJECT}.supabase.co/storage/v1/object/{BUCKET}/{KEY}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    with urllib.request.urlopen(req, timeout=30) as r:
        print(f"\nUploaded ({len(body)} bytes) status={r.status}")
        print(f"Public URL: https://{PROJECT}.supabase.co/storage/v1/object/public/{BUCKET}/{KEY}")


if __name__ == "__main__":
    main()
