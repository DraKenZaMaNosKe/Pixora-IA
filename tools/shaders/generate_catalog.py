"""
Generate realm_catalog.json from the hardcoded RealmCatalog list in
lib/features/realm/data/realm_catalog.dart, then upload to Supabase
Storage under wallpaper-shaders/realm_catalog.json + fire FCM `realm`
push so live clients refresh.

Parsing is minimal — looks for RealmShader(...) blocks and pulls each
field with a regex. Faster than a full Dart AST parser for our needs
and the manifest format is stable.
"""
import io
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_DART = ROOT / "lib/features/realm/data/realm_catalog.dart"
OUT_JSON = ROOT / "tools/shaders/realm_catalog.json"
KEYS = ROOT / "KEYS_LOCAL.md"
SUPABASE_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-shaders"
STORAGE_KEY = "realm_catalog.json"


def load_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key:\s*(\S+)", text)
    if not m:
        sys.exit("Could not find 'Service Role Key:' in KEYS_LOCAL.md")
    return m.group(1).strip()


def parse_dart_catalog() -> list[dict]:
    """Extract RealmShader entries from the Dart source file."""
    text = CATALOG_DART.read_text(encoding="utf-8")
    # Match RealmShader( ... ), capturing everything inside (lazy).
    entries = re.findall(r"RealmShader\((.*?)\),\s*$", text, re.DOTALL | re.MULTILINE)
    shaders = []
    for raw in entries:
        def field(name, default=None):
            m = re.search(rf"{name}:\s*'([^']*)'", raw)
            if m:
                return m.group(1)
            # Triple-quoted or multi-line strings
            m = re.search(rf"{name}:\s*\"([^\"]*)\"", raw)
            if m:
                return m.group(1)
            return default

        def enum_field(name):
            m = re.search(rf"{name}:\s*RealmCategory\.(\w+)", raw)
            if m:
                v = m.group(1)
                return "clock" if v == "clock" else "abstract"
            return "abstract"

        sid = field("id")
        if not sid:
            continue
        shaders.append({
            "id": sid,
            "name": field("name", ""),
            "description": field("description", ""),
            "category": enum_field("category"),
            "glowColor": field("glowColor", "#E6B655"),
            "previewKey": field("previewKey", ""),
            "badge": field("badge"),
        })
    return shaders


def upload_to_supabase(key: str, body: bytes) -> None:
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{STORAGE_KEY}"
    headers = {
        "Authorization": f"Bearer {key}",
        "apikey": key,
        "Content-Type": "application/json",
        "x-upsert": "true",
    }
    r = requests.post(url, headers=headers, data=body, timeout=30)
    if r.status_code not in (200, 201):
        sys.exit(f"upload failed {r.status_code}: {r.text[:300]}")


def fire_fcm() -> None:
    try:
        sys.path.insert(0, str(ROOT / "tools" / "wallpapers"))
        from _fcm_push import send_catalog_invalidate
        ok = send_catalog_invalidate("realm")
        print(f"  FCM push (realm): {'OK' if ok else 'FAILED'}")
    except Exception as e:
        print(f"  FCM push skipped: {e}")


def main() -> None:
    shaders = parse_dart_catalog()
    if not shaders:
        sys.exit("No shaders extracted from realm_catalog.dart")
    print(f"Parsed {len(shaders)} shaders from hardcoded catalog")
    by_cat = {}
    for s in shaders:
        by_cat[s["category"]] = by_cat.get(s["category"], 0) + 1
    for c, n in by_cat.items():
        print(f"  {c}: {n}")

    catalog = {
        "version": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "shaders": shaders,
    }
    body = json.dumps(catalog, ensure_ascii=False, indent=2).encode("utf-8")
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_bytes(body)
    print(f"\nWrote {OUT_JSON} ({len(body)} bytes)")

    print("\nUploading to Supabase Storage...")
    key = load_service_key()
    upload_to_supabase(key, body)
    print(f"  → {SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{STORAGE_KEY}")

    print("\nFiring FCM push...")
    fire_fcm()
    print("\nDone.")


if __name__ == "__main__":
    main()
