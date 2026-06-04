"""
Upload processed ringtones to Supabase Storage + merge into ringtones_catalog.json + FCM push.

Steps:
  1. For each pack in manifest:
     - Upload out/<pack>/<id>.mp3 → wallpaper-images/ringtones/<pack>/<id>.mp3
  2. Download current ringtones_catalog.json from Storage
  3. Merge new packs (new_pack=true) at the end + APPEND new tones to
     existing packs (new_pack=false)
  4. Upload merged catalog back to wallpaper-images/ringtones_catalog.json
  5. Fire FCM push scope='ringtones' to invalidate client caches

Reads SERVICE_KEY from KEYS_LOCAL.md (NOT anon key — service role required for Storage write).
"""
import io
import json
import re
import sys
from pathlib import Path

import requests

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
MANIFEST = ROOT / "manifest.json"
OUT = ROOT / "out"
KEYS = REPO / "KEYS_LOCAL.md"

SUPABASE_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
CATALOG_KEY = "ringtones_catalog.json"


def load_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    # Matches the canonical line in KEYS_LOCAL.md:
    #   - Service Role Key: eyJ...
    m = re.search(r"Service Role Key:\s*(\S+)", text)
    if not m:
        sys.exit("Could not find 'Service Role Key:' in KEYS_LOCAL.md")
    return m.group(1).strip()


def upload_file(key: str, storage_path: str, local: Path) -> None:
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{storage_path}"
    headers = {
        "Authorization": f"Bearer {key}",
        "apikey": key,
        "Content-Type": "audio/mpeg",
        "x-upsert": "true",
    }
    with open(local, "rb") as f:
        r = requests.post(url, headers=headers, data=f.read(), timeout=60)
    if r.status_code not in (200, 201):
        raise RuntimeError(f"upload failed {r.status_code}: {r.text[:200]}")


def upload_catalog(key: str, data: dict) -> None:
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{CATALOG_KEY}"
    headers = {
        "Authorization": f"Bearer {key}",
        "apikey": key,
        "Content-Type": "application/json",
        "x-upsert": "true",
    }
    body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
    r = requests.post(url, headers=headers, data=body, timeout=30)
    if r.status_code not in (200, 201):
        raise RuntimeError(f"catalog upload failed {r.status_code}: {r.text[:200]}")


def fetch_current_catalog() -> dict:
    url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{CATALOG_KEY}"
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.json()


def fire_fcm_push() -> None:
    """Best-effort: notify clients to refresh ringtones cache."""
    try:
        sys.path.insert(0, str(REPO / "tools" / "wallpapers"))
        from _fcm_push import send_catalog_invalidate  # type: ignore
        ok = send_catalog_invalidate("ringtones")
        print(f"  FCM push: {'OK' if ok else 'FAILED'}")
    except Exception as e:
        print(f"  FCM push skipped: {e}")


def main() -> None:
    key = load_service_key()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    print("═══ uploading processed ringtones ═══")
    uploaded = 0
    for pack in manifest["packs"]:
        pack_id = pack["id"]
        for t in pack["tones"]:
            local = OUT / pack_id / f"{t['id']}.mp3"
            if not local.exists():
                print(f"  -- skip {t['id']} (not processed)")
                continue
            storage_path = f"ringtones/{pack_id}/{t['id']}.mp3"
            try:
                upload_file(key, storage_path, local)
                print(f"  ok {storage_path}")
                uploaded += 1
            except Exception as e:
                print(f"  !! fail {storage_path}: {e}")
    print(f"  → {uploaded} files uploaded")

    print("\n═══ merging into ringtones_catalog.json ═══")
    current = fetch_current_catalog()
    existing_packs = {p["id"]: p for p in current.get("packs", [])}

    for pack in manifest["packs"]:
        pack_id = pack["id"]
        # Build tone entries in the catalog's expected shape (id/name/file/duration/suggestedType).
        new_tones = []
        for t in pack["tones"]:
            local = OUT / pack_id / f"{t['id']}.mp3"
            if not local.exists():
                continue
            new_tones.append({
                "id": t["id"],
                "name": t["name"],
                "file": f"ringtones/{pack_id}/{t['id']}.mp3",
                "duration": t["target_sec"],
                "suggestedType": t["suggestedType"],
            })
        if not new_tones:
            print(f"  -- pack {pack_id}: no tones ready, skipping")
            continue

        if pack.get("new_pack") and pack_id not in existing_packs:
            # Fresh pack — append at end.
            current.setdefault("packs", []).append({
                "id": pack_id,
                "name": pack["name"],
                "category": pack["category"],
                "description": pack["description"],
                "glowColor": pack["glowColor"],
                "previewImage": pack["previewImage"],
                "tones": new_tones,
            })
            print(f"  + new pack '{pack['name']}' with {len(new_tones)} tones")
        else:
            # Existing pack — APPEND tones (don't replace).
            existing = existing_packs.get(pack_id)
            if existing is None:
                print(f"  !! pack {pack_id} marked existing but not found in catalog")
                continue
            existing_ids = {t["id"] for t in existing.get("tones", [])}
            added = 0
            for t in new_tones:
                if t["id"] not in existing_ids:
                    existing.setdefault("tones", []).append(t)
                    added += 1
            print(f"  + appended {added} tones to '{existing['name']}'")

    # Bump version timestamp so clients know to re-fetch.
    from datetime import datetime, timezone
    current["version"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    upload_catalog(key, current)
    print("  ✓ catalog uploaded")

    print("\n═══ FCM invalidate ═══")
    fire_fcm_push()


if __name__ == "__main__":
    main()
