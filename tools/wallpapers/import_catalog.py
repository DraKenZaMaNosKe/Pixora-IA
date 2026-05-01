"""
Pixora Wallpapers — One-shot import from catalog.json -> Postgres `wallpapers` table.

Usage: python tools/wallpapers/import_catalog.py [--source PATH] [--dry-run]

Source defaults to the live Supabase catalog.json. Use --source to point at the
local catalog.FIXED.json instead.

Idempotent: uses INSERT ... ON CONFLICT (id) DO UPDATE so re-runs sync changes.
"""
from __future__ import annotations
import argparse, json, re, sys, urllib.request, urllib.error
from pathlib import Path

KEYS_PATH = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
DEFAULT_SOURCE = "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public/wallpaper-images/catalog.json"
PROJECT_REF = "vzuwvsmlyigjtsearxym"
RPC_URL = f"https://{PROJECT_REF}.supabase.co/rest/v1/wallpapers"


def get_service_key() -> str:
    content = KEYS_PATH.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", content)
    if not m:
        raise SystemExit("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


def load_catalog(source: str) -> list[dict]:
    if source.startswith("http"):
        with urllib.request.urlopen(source, timeout=30) as r:
            data = json.loads(r.read())
    else:
        data = json.loads(Path(source).read_text(encoding="utf-8"))
    return data.get("wallpapers", [])


# ---------- Mapping ----------
# Map JSON wallpaper -> row for the wallpapers table.
KNOWN_TYPES = {"static","live_video","parallax","shader","day_cycle","story","panoramic"}
KNOWN_CATEGORIES = {
    "WALLPAPERS","PANORAMIC","NATURE","ANIME","GAMING","MISC",
    "CALENDAR","ART","FANTASY","SCIFI","CULTURE","SCENES","SPECIAL",
    "CHRISTMAS","HORROR","ANIMALS","LIFESTYLE","UNIVERSE","DARK","AURA"
}
KNOWN_BADGES = {"NEW","HOT","PRO","FREE","LIMITED","BETA"}


def to_row(w: dict) -> dict:
    # Normalize type — JSON has 'image', 'live_video', etc.
    raw_type = (w.get("type") or "static").lower()
    if raw_type in ("image","static"): t = "static"
    elif raw_type in ("video","live_video","live"): t = "live_video"
    elif raw_type in ("parallax","scene","canvas_scene"): t = "parallax"
    elif raw_type == "shader": t = "shader"
    elif raw_type in ("day","day_cycle"): t = "day_cycle"
    elif raw_type == "story": t = "story"
    elif raw_type == "panoramic": t = "panoramic"
    else: t = "static"

    # Category: must be one of KNOWN; default WALLPAPERS
    cat = (w.get("category") or "WALLPAPERS").upper()
    if cat not in KNOWN_CATEGORIES: cat = "WALLPAPERS"

    # Badge: optional
    badge = w.get("badge")
    if badge and badge.upper() not in KNOWN_BADGES: badge = None
    elif badge: badge = badge.upper()

    # Tags: clean, lowercase, dedup
    tags = w.get("tags") or []
    tags = [str(t).strip().lower() for t in tags if t]
    seen = set()
    tags = [t for t in tags if not (t in seen or seen.add(t))][:25]

    return {
        "id":             w["id"],
        "name":           w["name"],
        "description":    (w.get("description") or w["name"])[:500],
        "type":           t,
        "category":       cat,
        "tags":           tags,
        "image_path":     w["imageFile"],
        "preview_path":   w.get("previewFile") or w["imageFile"],
        "image_size":     w.get("imageSize") or None,
        "preview_size":   w.get("previewSize") or None,
        "glow_color":     w.get("glowColor") or None,
        "badge":          badge,
        "sort_order":     w.get("sortOrder") if w.get("sortOrder") is not None else 1000,
        "featured":       bool(w.get("featured", False)),
        "published":      True,
    }


def upsert_rows(rows: list[dict], key: str, dry: bool) -> tuple[int,int]:
    if dry:
        print(f"[DRY] Would upsert {len(rows)} rows. First row:")
        print(json.dumps(rows[0], indent=2, ensure_ascii=False))
        return 0, 0

    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    # Batch in chunks of 100 to keep payload size reasonable
    inserted = 0
    failed = 0
    BATCH = 50
    for i in range(0, len(rows), BATCH):
        chunk = rows[i:i+BATCH]
        body = json.dumps(chunk, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(RPC_URL, data=body, method="POST")
        for k, v in headers.items(): req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                if 200 <= r.status < 300:
                    inserted += len(chunk)
                    print(f"  [{i+len(chunk):3d}/{len(rows)}] OK ({r.status})")
        except urllib.error.HTTPError as e:
            err_body = e.read().decode()
            print(f"  [{i:3d}+{len(chunk)}] HTTPError {e.code}: {err_body[:300]}")
            failed += len(chunk)
            # Try one-by-one to identify the bad row
            for row in chunk:
                req2 = urllib.request.Request(RPC_URL, data=json.dumps([row]).encode(), method="POST")
                for k, v in headers.items(): req2.add_header(k, v)
                try:
                    with urllib.request.urlopen(req2, timeout=30) as r2:
                        inserted += 1; failed -= 1
                except urllib.error.HTTPError as e2:
                    print(f"    BAD: id={row['id']} err={e2.read().decode()[:200]}")
    return inserted, failed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=DEFAULT_SOURCE)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    print(f"Source: {args.source}")
    catalog = load_catalog(args.source)
    print(f"Loaded: {len(catalog)} wallpapers")

    # Validate no dup IDs
    ids = [w["id"] for w in catalog]
    if len(ids) != len(set(ids)):
        from collections import Counter
        dups = {k:v for k,v in Counter(ids).items() if v>1}
        print(f"FATAL: duplicate ids: {dups}")
        return 2

    rows = [to_row(w) for w in catalog]

    # Show summary
    from collections import Counter
    print(f"By category: {dict(Counter(r['category'] for r in rows))}")
    print(f"By type:     {dict(Counter(r['type'] for r in rows))}")

    key = get_service_key()
    inserted, failed = upsert_rows(rows, key, args.dry_run)
    print(f"\nDone: inserted={inserted}, failed={failed}, total={len(rows)}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
