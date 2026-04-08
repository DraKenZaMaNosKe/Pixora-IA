"""
Upload all AURA audio files to bucket 'aura-audio' and upsert rows
in public.aura_tracks. Reads service role key from KEYS_LOCAL.md.
"""
import json
import re
import subprocess
import sys
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
MANIFEST = ROOT / "tracks_manifest.json"
KEYS = REPO / "KEYS_LOCAL.md"

PROJECT = "vzuwvsmlyigjtsearxym"
BASE = f"https://{PROJECT}.supabase.co"
BUCKET = "aura-audio"


def load_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key:\s*(\S+)", text)
    if not m:
        sys.exit("Could not find 'Service Role Key:' in KEYS_LOCAL.md")
    return m.group(1)


KEY = load_service_key()
HEADERS = {"apikey": KEY, "Authorization": f"Bearer {KEY}"}


def ffprobe_duration(p: Path) -> int:
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nokey=1:noprint_wrappers=1", str(p)],
        capture_output=True, text=True, check=True)
    return int(float(r.stdout.strip()))


def upload(file: Path, dest_path: str) -> str:
    url = f"{BASE}/storage/v1/object/{BUCKET}/{dest_path}"
    with open(file, "rb") as f:
        r = requests.post(
            url,
            headers={**HEADERS, "Content-Type": "audio/mpeg", "x-upsert": "true"},
            data=f, timeout=300,
        )
    if r.status_code not in (200, 201):
        raise RuntimeError(f"upload failed {r.status_code}: {r.text[:300]}")
    return f"{BASE}/storage/v1/object/public/{BUCKET}/{dest_path}"


def upsert(row: dict) -> None:
    url = f"{BASE}/rest/v1/aura_tracks"
    r = requests.post(
        url,
        headers={
            **HEADERS,
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        },
        json=[row], timeout=30,
    )
    if r.status_code not in (200, 201, 204):
        raise RuntimeError(f"upsert failed {r.status_code}: {r.text[:300]}")


def main() -> None:
    m = json.loads(MANIFEST.read_text(encoding="utf-8"))
    log_path = ROOT / "fetch_log.json"
    log = {e["id"]: e for e in json.loads(log_path.read_text())} if log_path.exists() else {}

    sort = 0
    for t in m["frequencies"]:
        local = ROOT / t["file"]
        dest = f"frequencies/{Path(t['file']).name}"
        url = upload(local, dest)
        upsert({
            "id": t["id"],
            "category": "frequency",
            "hz": t["hz"],
            "chakra": t["chakra"],
            "color_hex": t["color_hex"],
            "icon": None,
            "name_en": t["name_en"],
            "name_es": t["name_es"],
            "desc_en": t["desc_en"],
            "desc_es": t["desc_es"],
            "duration_sec": ffprobe_duration(local),
            "file_path": dest,
            "audio_url": url,
            "license": "GENERATED",
            "freesound_id": None,
            "freesound_user": None,
            "sort_order": sort,
        })
        print(f"freq  {t['id']}  -> {url}")
        sort += 1

    sort = 0
    for t in m["nature"]:
        local = ROOT / t["file"]
        dest = f"nature/{Path(t['file']).name}"
        url = upload(local, dest)
        meta = log.get(t["id"], {})
        upsert({
            "id": t["id"],
            "category": "nature",
            "hz": None,
            "chakra": None,
            "color_hex": None,
            "icon": t["icon"],
            "name_en": t["name_en"],
            "name_es": t["name_es"],
            "desc_en": t["desc_en"],
            "desc_es": t["desc_es"],
            "duration_sec": ffprobe_duration(local),
            "file_path": dest,
            "audio_url": url,
            "license": t["license"],
            "freesound_id": meta.get("freesound_id"),
            "freesound_user": meta.get("freesound_user"),
            "sort_order": sort,
        })
        print(f"nat   {t['id']}  -> {url}")
        sort += 1

    print("\nDone.")


if __name__ == "__main__":
    main()
