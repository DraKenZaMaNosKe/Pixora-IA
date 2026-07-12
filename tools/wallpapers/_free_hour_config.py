"""Enable / disable / tune the Free Hour feature remotely (no app release).

Uploads free_hour_config.json to the public wallpaper-images bucket. The app
reads it (TTL 30 min + on resume). Default in the app is OFF, so the feature
only turns on once this JSON exists with "enabled": true.

Usage:
  python _free_hour_config.py on          # enable (8pm local, 7 min, notify)
  python _free_hour_config.py off         # KILL-SWITCH: disable everywhere
  python _free_hour_config.py on --hour 20 --dur 10 --no-notify
"""
import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
REMOTE = "free_hour_config.json"

SK = re.findall(
    r"eyJ[A-Za-z0-9_\-\.]{100,500}",
    Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"),
)[0]


def put(body: bytes):
    req = urllib.request.Request(
        f"{PROJECT}/storage/v1/object/{BUCKET}/{REMOTE}", data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}")
    req.add_header("apikey", SK)
    req.add_header("Content-Type", "application/json")
    req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=60) as r:
        print(f"PUT {BUCKET}/{REMOTE} -> {r.status}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("state", choices=["on", "off"])
    ap.add_argument("--dur", type=int, default=7, help="duration minutes (1-240)")
    ap.add_argument("--hour", type=int, default=20, help="start hour local (0-23), 8pm=20")
    ap.add_argument("--minute", type=int, default=0, help="start minute (0-59)")
    ap.add_argument("--no-notify", action="store_true")
    a = ap.parse_args()

    cfg = {
        "enabled": a.state == "on",
        "duration_min": a.dur,
        "hour": a.hour,
        "minute": a.minute,
        "notify": not a.no_notify,
    }
    # Sanity (mirrors the app's validation — invalid = OFF client-side anyway).
    assert 1 <= a.dur <= 240, "dur out of range"
    assert 0 <= a.hour <= 23 and 0 <= a.minute < 60, "time invalid"
    assert (a.hour * 60 + a.minute + a.dur) <= 24 * 60, "window crosses midnight"

    print(json.dumps(cfg, indent=2))
    put(json.dumps(cfg, indent=2).encode("utf-8"))
    if a.state == "on":
        print("\nHora Free ACTIVADA. Llega a los usuarios en ≤30 min (TTL) o al "
              "próximo resume de la app.")
    else:
        print("\nHora Free DESACTIVADA (kill-switch). Mismo lag de propagación.")


if __name__ == "__main__":
    main()
