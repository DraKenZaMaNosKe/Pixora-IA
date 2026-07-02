"""Process locally-downloaded mp3s + upload + manifest update.

Igual que process_and_upload.py pero el source es un archivo local (no
descarga de Freesound). Cada entry mapea: archivo local → pack destino
→ tone_id. Aplica el mismo loudnorm + trim + upload + catalog merge.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
CATALOG_FILE = "ringtones_catalog.json"
ROOT = Path(__file__).parent
OUT_DIR = ROOT / "out" / "_manual_processed"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def load_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", text)
    if not m:
        sys.exit("Could not find Service Role Key in KEYS_LOCAL.md")
    return m.group(1)


def process_audio(src: Path, dst: Path, target_sec: int) -> tuple[bool, float]:
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


def storage_put(key: str, remote: str, body: bytes, ct: str) -> bool:
    url = f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", ct)
    req.add_header("x-upsert", "true")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status < 400
    except Exception as e:
        print(f"   ! storage put: {e}")
        return False


def fetch_catalog() -> dict:
    url = f"{PROJECT}/storage/v1/object/public/{BUCKET}/{CATALOG_FILE}"
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            return json.loads(r.read())
    except Exception:
        return {"version": 1, "packs": []}


def put_catalog(key: str, catalog: dict) -> bool:
    body = json.dumps(catalog, indent=2, ensure_ascii=False).encode("utf-8")
    return storage_put(key, CATALOG_FILE, body, "application/json")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mapping_json")
    args = ap.parse_args()

    config = json.loads(Path(args.mapping_json).read_text(encoding="utf-8"))
    source_dir = Path(config["_meta"]["source_dir"])
    print(f"\n{'='*60}")
    print(f"Source: {source_dir}")
    print(f"Files: {len(config['files'])}")
    print(f"⚠ {config['_meta'].get('warning', '')}")
    print(f"{'='*60}\n")

    service_key = load_service_key()
    catalog = fetch_catalog()
    by_pack: dict[str, list[dict]] = {}

    for entry in config["files"]:
        src_path = source_dir / entry["src_filename"]
        if not src_path.exists():
            print(f"[SKIP] {entry['src_filename']}: not found")
            continue
        tone_id = entry["tone_id"]
        pack_id = entry["target_pack"]
        name = entry["name"]
        target = entry["target_sec"]
        sug = entry.get("suggestedType", "notification")

        print(f"  · {tone_id:30s} → pack {pack_id}")
        out_path = OUT_DIR / f"{tone_id}.mp3"
        ok, actual = process_audio(src_path, out_path, target)
        if not ok:
            continue

        # Subfolder name (gaming, retro, modern, internet_nostalgia, memes)
        subfolder = pack_id.replace("_pack", "")
        remote = f"ringtones/{subfolder}/{tone_id}.mp3"
        body = out_path.read_bytes()
        if not storage_put(service_key, remote, body, "audio/mpeg"):
            continue
        print(f"       PUT {remote}  ({len(body):,} B, {actual:.2f}s)")

        # IMPORTANT: duration MUST be int — Flutter RingtoneTone.fromJson
        # crashes on double. 2026-06-23 fix.
        by_pack.setdefault(pack_id, []).append({
            "id": tone_id,
            "name": name,
            "file": remote,
            "duration": max(1, round(actual)),
            "suggestedType": sug,
            "source": "manual_upload",
        })

    if not by_pack:
        print("\n[!] Ninguno procesado.")
        return

    # Merge each pack
    print(f"\n[catalog] Mergeando en {len(by_pack)} packs...")
    for pack_id, new_tones in by_pack.items():
        idx = next((i for i, p in enumerate(catalog["packs"]) if p.get("id") == pack_id), -1)
        if idx < 0:
            print(f"  [!] Pack {pack_id} no existe en catalog. Skip.")
            continue
        existing = catalog["packs"][idx]
        existing_tones = {t["id"]: t for t in existing.get("tones", [])}
        for t in new_tones:
            existing_tones[t["id"]] = t
        catalog["packs"][idx]["tones"] = list(existing_tones.values())
        print(f"  · pack {pack_id} ahora con {len(catalog['packs'][idx]['tones'])} tonos (+{len(new_tones)})")

    if not put_catalog(service_key, catalog):
        sys.exit("[!] Fallo subiendo catalog")
    print(f"  PUT {CATALOG_FILE} OK")

    print("\n[FCM] invalidate ringtones...")
    try:
        sys.path.insert(0, str(ROOT.parent / "wallpapers"))
        from _fcm_push import send_catalog_invalidate
        print(f"  -> {send_catalog_invalidate('ringtones')}")
    except Exception as e:
        print(f"  ! FCM fallo (no critical): {e}")

    total = sum(len(v) for v in by_pack.values())
    print(f"\n[OK] {total} tonos manuales subidos.")


if __name__ == "__main__":
    main()
