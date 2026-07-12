"""Enable / disable / tune the Free Hour feature remotely (no app release).

Uploads free_hour_config.json to the public wallpaper-images bucket. The app
reads it (TTL 30 min + on resume). Default in the app is OFF, so the feature
only turns on once this JSON exists with "enabled": true.

Usage:
  python _free_hour_config.py on          # enable (30 min, 7-23h, notify)
  python _free_hour_config.py off         # KILL-SWITCH: disable everywhere
  python _free_hour_config.py on --dur 45 --start 8 --end 22 --no-notify
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
    ap.add_argument("--dur", type=int, default=30, help="duration minutes (5-120)")
    ap.add_argument("--start", type=int, default=7, help="window start hour (0-23)")
    ap.add_argument("--end", type=int, default=23, help="window end hour (1-24)")
    ap.add_argument("--no-notify", action="store_true")
    a = ap.parse_args()

    cfg = {
        "enabled": a.state == "on",
        "duration_min": a.dur,
        "window_start_hour": a.start,
        "window_end_hour": a.end,
        "notify": not a.no_notify,
    }
    # Sanity (mirrors the app's validation — invalid = OFF client-side anyway).
    assert 5 <= a.dur <= 120, "dur out of range"
    assert 0 <= a.start < a.end <= 24, "window invalid"
    assert (a.end * 60 - a.dur) > (a.start * 60), "window too small for duration"

    print(json.dumps(cfg, indent=2))
    put(json.dumps(cfg, indent=2).encode("utf-8"))
    if a.state == "on":
        print("\nHora Free ACTIVADA. Llega a los usuarios en ≤30 min (TTL) o al "
              "próximo resume de la app.")
    else:
        print("\nHora Free DESACTIVADA (kill-switch). Mismo lag de propagación.")


if __name__ == "__main__":
    main()
