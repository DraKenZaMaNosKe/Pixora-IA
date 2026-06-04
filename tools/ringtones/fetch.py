"""
Fetch ringtones from Freesound — CC0-licensed, short clips.

Reads tools/ringtones/manifest.json, searches Freesound for each tone
(filter: CC0, duration <= 30s preferred), downloads the preview MP3 to
tools/ringtones/raw/<pack>/<id>.mp3.

Idempotent: if raw file exists and >1KB, skip. Run multiple times safely.

Token read from KEYS_LOCAL.md.
"""
import io
import json
import re
import sys
from pathlib import Path

import requests

# Windows console default is cp1252; force UTF-8 so our box-drawing chars work.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
MANIFEST = ROOT / "manifest.json"
RAW_DIR = ROOT / "raw"
KEYS = REPO / "KEYS_LOCAL.md"

API = "https://freesound.org/apiv2"


def load_token() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"API Key \(client secret\):\s*(\S+)", text)
    if not m:
        sys.exit("Could not find Freesound API key in KEYS_LOCAL.md")
    return m.group(1)


def search(token: str, query: str, max_duration: int = 30) -> dict | None:
    """Return the highest-rated CC0 result short enough for a ringtone.
    Ringtones are typically 1-30s. Notification sounds 1-5s."""
    params = {
        "query": query,
        # Slightly wider window than target — process.py will trim to spec.
        # Min 0.3s catches very short SFX, max 60s gives processing headroom.
        "filter": f'license:"Creative Commons 0" duration:[0.3 TO 60]',
        "sort": "rating_desc",
        "fields": "id,name,duration,license,download,previews,username,avg_rating",
        "page_size": 5,
        "token": token,
    }
    r = requests.get(f"{API}/search/text/", params=params, timeout=30)
    if r.status_code != 200:
        print(f"   ! HTTP {r.status_code}: {r.text[:200]}")
        return None
    results = r.json().get("results", [])
    return results[0] if results else None


def download_preview(token: str, sound: dict, dest: Path) -> None:
    url = sound["previews"]["preview-hq-mp3"]
    r = requests.get(url, params={"token": token}, stream=True, timeout=120)
    r.raise_for_status()
    dest.parent.mkdir(parents=True, exist_ok=True)
    with open(dest, "wb") as f:
        for chunk in r.iter_content(8192):
            f.write(chunk)


def main() -> None:
    token = load_token()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    log = []
    for pack in manifest["packs"]:
        pack_id = pack["id"]
        pack_dir = RAW_DIR / pack_id
        print(f"\n═══ pack: {pack['name']} ({len(pack['tones'])} tones) ═══")
        for t in pack["tones"]:
            dest = pack_dir / f"{t['id']}.mp3"
            if dest.exists() and dest.stat().st_size > 1024:
                print(f"-- skip {t['id']} (cached, {dest.stat().st_size} B)")
                log.append({"pack": pack_id, "id": t["id"], "status": "cached"})
                continue
            q = t["freesound_query"]
            print(f">> '{q}' for {t['id']}")
            hit = search(token, q)
            if not hit:
                print("   NO RESULT")
                log.append({"pack": pack_id, "id": t["id"], "status": "no_result", "query": q})
                continue
            try:
                download_preview(token, hit, dest)
            except Exception as e:
                print(f"   ! download error: {e}")
                log.append({"pack": pack_id, "id": t["id"], "status": "download_error", "error": str(e)})
                continue
            print(f"   ok id={hit['id']} '{hit['name']}' by {hit['username']} -> {dest.name}")
            log.append({
                "pack": pack_id,
                "id": t["id"],
                "status": "ok",
                "freesound_id": hit["id"],
                "freesound_name": hit["name"],
                "freesound_user": hit["username"],
                "freesound_rating": hit["avg_rating"],
                "duration": hit["duration"],
            })
    (ROOT / "fetch_log.json").write_text(json.dumps(log, indent=2))
    ok = sum(1 for e in log if e["status"] in ("ok", "cached"))
    print(f"\nDone. {ok}/{len(log)} ready. Log: {ROOT/'fetch_log.json'}")


if __name__ == "__main__":
    main()
