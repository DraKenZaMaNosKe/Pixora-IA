"""
Bulk-upload all 96 personalised lunar phase variants to Supabase Storage.
Skips files that have no `_NN` (sign-index) suffix — those were the
generic phase-only baseline already uploaded.
"""
from __future__ import annotations
import re, sys, urllib.request, urllib.error
from pathlib import Path
import time

sys.stdout.reconfigure(encoding="utf-8")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
SRC_DIR = Path(r"D:/Orbix/Pixora-IA/docs/design/concepts/livecalendar/egyptian/panoramic_phases")
PROJECT_REF = "vzuwvsmlyigjtsearxym"
BUCKET = "wallpaper-images"


def get_service_key() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)", text)
    if not m:
        raise SystemExit("Service Role Key not found in KEYS_LOCAL.md")
    return m.group(1)


SVC = get_service_key()


def upload(name: str, body: bytes) -> bool:
    url = f"https://{PROJECT_REF}.supabase.co/storage/v1/object/{BUCKET}/{name}"
    req = urllib.request.Request(url, data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("Content-Type", "image/webp")
    req.add_header("x-upsert", "true")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status in (200, 201)
    except urllib.error.HTTPError as e:
        print(f"  ! {name}: HTTP {e.code}")
        return False
    except Exception as e:
        print(f"  ! {name}: {e}")
        return False


# Match only the personalised filenames (with _NN sign suffix)
PATTERN = re.compile(r"pixora_iah_egyptian_giza_lunar_[a-z_]+_(\d{2})\.webp$")

files = sorted([p for p in SRC_DIR.glob("*.webp") if PATTERN.match(p.name)])
print(f"Found {len(files)} personalised variants in {SRC_DIR}\n")

start = time.time()
ok_count = 0
for i, f in enumerate(files, 1):
    body = f.read_bytes()
    if upload(f.name, body):
        ok_count += 1
        if i % 10 == 0:
            elapsed = time.time() - start
            print(f"  [{i}/{len(files)}] {ok_count} ok  ({elapsed:.0f}s)")

elapsed = time.time() - start
print(f"\n{ok_count}/{len(files)} uploaded in {elapsed:.0f}s ({ok_count/elapsed*60:.1f}/min)")
