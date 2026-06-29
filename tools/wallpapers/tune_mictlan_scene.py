"""
Tune Mictlantecuhtli sprite size + position. Edit the two variables below,
run, and the spec is patched + index bumped + device cache cleared in one
shot. Usage: python tools/wallpapers/tune_mictlan_scene.py
"""
import json, os, re, subprocess, urllib.request
from pathlib import Path

# ─── EDIT THESE TO ITERATE SIZE/POSITION ──────────────────────────────
SPRITE_SCALE = 0.0022   # sprite size factor. Higher = bigger.
                        # Reference: 0.0011 was tiny, try 0.0022 (2x) first
SPRITE_Y     = 0.82     # vertical position 0..1 (0=top, 1=bottom).
                        # Lower as scale grows so feet stay on the floor
SPRITE_X     = 0.50     # horizontal position 0..1 (0.5 = centered)
# ──────────────────────────────────────────────────────────────────────

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
SVC = re.search(r"Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)",
                KEYS.read_text(encoding="utf-8")).group(1)
PROJECT = "vzuwvsmlyigjtsearxym"
DEV = "RF8X903KZ3K"


def put(bucket, key, body, ctype):
    req = urllib.request.Request(
        f"https://{PROJECT}.supabase.co/storage/v1/object/{bucket}/{key}",
        data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SVC}")
    req.add_header("Content-Type", ctype)
    req.add_header("x-upsert", "true")
    return urllib.request.urlopen(req, timeout=30).status


# 1. Patch spec
spec = json.loads(urllib.request.urlopen(
    f"https://{PROJECT}.supabase.co/storage/v1/object/public/wallpaper-scenes/mictlantecuhtli.json",
    timeout=30).read())
spec["sprites"][0]["params"]["scale"] = SPRITE_SCALE
spec["sprites"][0]["params"]["x"] = SPRITE_X
spec["sprites"][0]["params"]["y"] = SPRITE_Y
body = json.dumps(spec, ensure_ascii=False, indent=2).encode("utf-8")
put("wallpaper-scenes", "mictlantecuhtli.json", body, "application/json")
print(f"Spec updated: scale={SPRITE_SCALE}, x={SPRITE_X}, y={SPRITE_Y}")

# 2. Bump catalog_index version (forces app re-fetch of spec)
idx = json.loads(urllib.request.urlopen(
    f"https://{PROJECT}.supabase.co/storage/v1/object/public/wallpaper-images/catalog_index.json",
    timeout=30).read())
idx["version"] = idx.get("version", 27) + 1
put("wallpaper-images", "catalog_index.json",
    json.dumps(idx, ensure_ascii=False, indent=2).encode("utf-8"),
    "application/json")
print(f"Catalog index bumped to v{idx['version']}")

# 3. Clear device cache + relaunch (sin ventana adb)
ADB = r"C:\Users\lalo\AppData\Local\Android\Sdk\platform-tools\adb.exe"
flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
subprocess.run([ADB, "-s", DEV, "shell", "run-as", "com.orbix.pixora",
                "rm", "-f", "files/catalog_index.json"], check=False, creationflags=flags)
subprocess.run([ADB, "-s", DEV, "shell", "run-as", "com.orbix.pixora",
                "rm", "-rf", "files/scene_specs"], check=False, creationflags=flags)
subprocess.run([ADB, "-s", DEV, "shell", "am", "force-stop",
                "com.orbix.pixora"], check=False, creationflags=flags)
subprocess.run([ADB, "-s", DEV, "shell", "am", "start",
                "-n", "com.orbix.pixora/.MainActivity"], check=False, creationflags=flags)
print("Device cache cleared, Pixora relaunched.")
print()
print("Open Pixora -> 3D tab -> Mictlantecuhtli -> Apply again.")
print("(The sprites stay cached so re-apply is fast — only spec re-downloads.)")
