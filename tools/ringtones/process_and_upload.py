"""Process selected Freesound tones + upload + manifest update.

Pipeline:
  1. Load _selected_*.json (output del audition tool)
  2. Download each freesound_id → preview-hq-mp3
  3. ffmpeg normalize (loudnorm -16 LUFS) + trim a target_sec
  4. PUT al Supabase Storage en ringtones/{pack_id}/{tone_id}.mp3
  5. Mergea/agrega pack en ringtones_catalog.json
  6. FCM invalidate (catalog 'ringtones')

Idempotente: si el archivo MP3 ya existe en cache local, salta descarga.
Si el pack ya existe en catalog, agrega/reemplaza tones por id.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

import requests

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
CATALOG_FILE = "ringtones_catalog.json"
ROOT = Path(__file__).parent
RAW_DIR = ROOT / "raw" / "_downloads"
OUT_DIR = ROOT / "out" / "_processed"
RAW_DIR.mkdir(parents=True, exist_ok=True)
OUT_DIR.mkdir(parents=True, exist_ok=True)

API = "https://freesound.org/apiv2"


def load_freesound_token() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"API Key \(client secret\):\s*(\S+)", text)
    if not m:
        sys.exit("Could not find Freesound API key in KEYS_LOCAL.md")
    return m.group(1)


def load_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", text)
    if not m:
        sys.exit("Could not find Supabase Service Role Key in KEYS_LOCAL.md")
    return m.group(1)


def _auth_headers(token: str) -> dict:
    """Freesound API v2 accepts API key via Authorization header — preferred
    over ?token= query param to avoid leaking the secret into proxy logs,
    error messages, and process snapshots. Format: 'Token <key>' (not Bearer,
    which is reserved for OAuth2 user tokens)."""
    return {"Authorization": f"Token {token}"}


def fetch_freesound_info(token: str, fs_id: int) -> dict | None:
    """Fetch metadata for one sound."""
    url = f"{API}/sounds/{fs_id}/"
    r = requests.get(url, headers=_auth_headers(token), timeout=20)
    if r.status_code != 200:
        print(f"   ! HTTP {r.status_code} for FS#{fs_id}")
        return None
    return r.json()


def download_preview(token: str, info: dict, dest: Path) -> bool:
    """Download preview-hq-mp3 to dest. Preview URLs are public on Freesound's
    CDN (no auth needed) so we drop the token entirely for downloads.
    Returns True if downloaded ok."""
    url = info.get("previews", {}).get("preview-hq-mp3")
    if not url:
        print(f"   ! No preview-hq-mp3 for FS#{info['id']}")
        return False
    try:
        r = requests.get(url, stream=True, timeout=120)
        r.raise_for_status()
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "wb") as f:
            for chunk in r.iter_content(8192):
                f.write(chunk)
        return True
    except Exception as e:
        print(f"   ! download failed: {e}")
        return False


def process_audio(src: Path, dst: Path, target_sec: int) -> tuple[bool, float]:
    """ffmpeg loudnorm + trim. Returns (ok, actual_duration)."""
    # First get input duration via ffprobe
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", str(src)],
            capture_output=True, text=True, check=True
        )
        input_dur = float(r.stdout.strip())
    except Exception as e:
        print(f"   ! ffprobe failed: {e}")
        return False, 0.0

    # Trim to min(target_sec, input_dur). Apply fade-out 0.15s at end.
    actual = min(target_sec, input_dur)
    fade_start = max(0, actual - 0.15)
    af = (
        f"atrim=0:{actual:.3f},"
        f"afade=t=out:st={fade_start:.3f}:d=0.15,"
        f"loudnorm=I=-16:LRA=11:TP=-1.5"
    )
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(src),
        "-af", af,
        "-ar", "44100", "-b:a", "128k", "-codec:a", "libmp3lame",
        str(dst),
    ]
    try:
        subprocess.run(cmd, check=True)
        return True, actual
    except subprocess.CalledProcessError as e:
        print(f"   ! ffmpeg failed: {e}")
        return False, 0.0


def storage_put(service_key: str, remote_path: str, body: bytes, ct: str) -> bool:
    url = f"{PROJECT}/storage/v1/object/{BUCKET}/{remote_path}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {service_key}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status < 400
    except Exception as e:
        print(f"   ! storage put failed: {e}")
        return False


def fetch_catalog(service_key: str) -> dict:
    url = f"{PROJECT}/storage/v1/object/public/{BUCKET}/{CATALOG_FILE}"
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            return json.loads(r.read())
    except Exception:
        return {"version": 1, "packs": []}


def put_catalog(service_key: str, catalog: dict) -> bool:
    body = json.dumps(catalog, indent=2, ensure_ascii=False).encode("utf-8")
    return storage_put(service_key, CATALOG_FILE, body, "application/json")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("selection_json", help="Path to _selected_*.json from audition tool")
    args = ap.parse_args()

    sel_path = Path(args.selection_json)
    if not sel_path.exists():
        sys.exit(f"Not found: {sel_path}")

    selection = json.loads(sel_path.read_text(encoding="utf-8"))
    meta = selection.get("_meta", {})
    pack_id = meta.get("pack_id") or sys.exit("_meta.pack_id required")
    pack_name = meta.get("pack_name", pack_id)
    pack_desc = meta.get("pack_description", "")
    pack_glow = meta.get("pack_glow", "#4ECDC4")
    pack_category = meta.get("pack_category", "RETRO")
    slots = selection.get("slots", {})

    print(f"\n{'='*60}")
    print(f"Procesando pack: {pack_name} ({pack_id})")
    print(f"{'='*60}\n")

    fs_token = load_freesound_token()
    service_key = load_service_key()

    # Build new pack tones[]
    pack_tones = []
    for slot_id, candidates in slots.items():
        if not candidates:
            continue
        for idx, cand in enumerate(candidates):
            # Tone id: si solo hay 1, usar slot_id; si varios, sufijo numérico.
            tone_id = slot_id if len(candidates) == 1 else f"{slot_id}_{idx+1}"
            fs_id = cand["freesound_id"]
            target = cand.get("target_sec", 3)
            name = cand.get("name_human") or f"{slot_id} #{idx+1}"

            print(f"  · {tone_id:35s} FS#{fs_id}  target={target}s  '{name}'")

            # 1) Fetch info from Freesound
            info = fetch_freesound_info(fs_token, fs_id)
            if not info:
                continue

            # 2) Download preview
            raw_path = RAW_DIR / f"fs_{fs_id}.mp3"
            if not raw_path.exists() or raw_path.stat().st_size < 1024:
                if not download_preview(fs_token, info, raw_path):
                    continue
            else:
                print(f"       (cached raw)")

            # 3) Process: trim + normalize
            out_path = OUT_DIR / f"{tone_id}.mp3"
            ok, actual_dur = process_audio(raw_path, out_path, target)
            if not ok:
                continue

            # 4) Upload to Storage
            remote = f"ringtones/{pack_id.replace('_pack','')}/{tone_id}.mp3"
            body = out_path.read_bytes()
            if not storage_put(service_key, remote, body, "audio/mpeg"):
                continue
            print(f"       PUT {remote}  ({len(body):,} B, {actual_dur:.2f}s)")

            # 5) Determine suggestedType (ringtone if >= 3s, notification otherwise)
            sug = "ringtone" if actual_dur >= 3.0 else "notification"

            # IMPORTANT: duration MUST be int — Flutter RingtoneTone.fromJson
            # uses `json['duration'] as int?` which throws TypeError on
            # double, breaking the WHOLE pack parse (one bad tone = "No
            # tones available yet" across the app). Round up to nearest
            # second, min 1. 2026-06-23 bug fix.
            pack_tones.append({
                "id": tone_id,
                "name": name,
                "file": remote,
                "duration": max(1, round(actual_dur)),
                "suggestedType": sug,
                "freesound_credit": {
                    "id": fs_id,
                    "user": info.get("username"),
                    "license": info.get("license"),
                },
            })

    if not pack_tones:
        print("\n[!] No tones procesados. Abort.")
        return

    # 6) Merge into catalog
    print(f"\n[catalog] Mergeando {len(pack_tones)} tonos en pack {pack_id}...")
    catalog = fetch_catalog(service_key)
    existing_idx = next(
        (i for i, p in enumerate(catalog.get("packs", [])) if p.get("id") == pack_id),
        -1,
    )
    new_pack = {
        "id": pack_id,
        "name": pack_name,
        "description": pack_desc,
        "previewImage": f"ringtone_{pack_id.replace('_pack','')}_preview.webp",
        "glowColor": pack_glow,
        "category": pack_category,
        "tones": pack_tones,
    }
    if existing_idx >= 0:
        # Merge tones by id (new replaces existing same-id)
        existing = catalog["packs"][existing_idx]
        existing_tones = {t["id"]: t for t in existing.get("tones", [])}
        for t in pack_tones:
            existing_tones[t["id"]] = t
        new_pack["tones"] = list(existing_tones.values())
        catalog["packs"][existing_idx] = new_pack
        print(f"  pack ya existía → mergeado ({len(new_pack['tones'])} tonos totales)")
    else:
        catalog.setdefault("packs", []).append(new_pack)
        print(f"  pack nuevo → agregado")

    if not put_catalog(service_key, catalog):
        sys.exit("[!] Fallo subiendo catalog")
    print(f"  PUT {CATALOG_FILE} OK")

    # 7) FCM invalidate
    print("\n[FCM] invalidate ringtones...")
    try:
        sys.path.insert(0, str(ROOT.parent / "wallpapers"))
        from _fcm_push import send_catalog_invalidate
        print(f"  -> {send_catalog_invalidate('ringtones')}")
    except Exception as e:
        print(f"  ! FCM fallo (no critical): {e}")

    print(f"\n[OK] Pack {pack_id} con {len(pack_tones)} tonos publicado.")


if __name__ == "__main__":
    main()
