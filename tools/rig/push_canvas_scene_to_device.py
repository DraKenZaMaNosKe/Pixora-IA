"""Aplica una canvas_scene de tipo SPRITE+LAYERS (no rig) en un device por
cable: baja spec + image_layers + master + el/los sprite(s) ZIP (descomprime
sus frames), los empuja a filesDir, setea scene_id en prefs y reinicia SOLO el
proceso :wallpaper (kill por pid, NO force-stop).

Lee el spec publicado para descubrir layers y sprites — sirve para cualquier
canvas_scene sprite+layers, no solo el Goku.

Uso: [ADB_DEVICE=<serial>] python push_canvas_scene_to_device.py <SID>
"""
import subprocess, sys, time, re, os, zipfile, json, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
D = os.environ.get("ADB_DEVICE", "RF8X903KZ3K"); PKG = "com.orbix.pixora"
PUB = "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public"
SID = sys.argv[1]
TMP = Path("_cstmp"); TMP.mkdir(exist_ok=True)

def dl(url, dst): open(dst, "wb").write(urllib.request.urlopen(f"{url}?nc={int(time.time())}", timeout=90).read())
def adb(*a): return subprocess.run(["adb", "-s", D, *a], capture_output=True, text=True)
def runas(cmd): return subprocess.run(["adb", "-s", D, "shell", f"run-as {PKG} sh -c '{cmd}'"], capture_output=True, text=True)
def pushf(local, dest):
    adb("push", str(local), "/data/local/tmp/_p.bin")
    d = dest.rsplit("/", 1)[0] if "/" in dest else ""
    if d: runas(f"mkdir -p files/{d}")
    r = runas(f"cat /data/local/tmp/_p.bin > files/{dest}")
    print(f"  {'✓' if r.returncode == 0 else '✗'} files/{dest}")

subprocess.run(["adb", "reconnect", "offline"], capture_output=True); time.sleep(2)
if adb("shell", "true").returncode != 0:
    subprocess.run(["adb", "kill-server"]); time.sleep(1); subprocess.run(["adb", "start-server"]); time.sleep(2)

print(f"== bajando spec de {SID} ==")
dl(f"{PUB}/wallpaper-scenes/{SID}.json", TMP / "spec.json")
spec = json.loads((TMP / "spec.json").read_text(encoding="utf-8"))
pushf(TMP / "spec.json", f"scene_specs/{SID}.json")

print("== image_layers ==")
for l in spec.get("image_layers", []):
    key = l.get("key"); url = l.get("url")
    if not url: continue
    dl(url, TMP / f"layer_{key}.webp")
    pushf(TMP / f"layer_{key}.webp", f"scene_layers/{SID}/{key}.webp")

print("== master (flat) ==")
try:
    dl(f"{PUB}/wallpaper-images/{SID}.webp", TMP / "master.webp")
    pushf(TMP / "master.webp", f"{SID}_master.webp")
except Exception as e:
    print("  · master:", e)

print("== sprites (zip -> frames) ==")
manifest = json.loads(urllib.request.urlopen(f"{PUB}/wallpaper-sprites/manifest.json?nc={int(time.time())}", timeout=30).read())
for s in spec.get("sprites", []):
    mk = s.get("manifest_key"); m = manifest.get(mk)
    if not m: print(f"  · sin manifest para {mk}"); continue
    dl(f"{PUB}/wallpaper-sprites/{m['zip']}", TMP / "spr.zip")
    fr = TMP / "frames"; fr.mkdir(exist_ok=True)
    for f in fr.glob("*"): f.unlink()
    with zipfile.ZipFile(TMP / "spr.zip") as zf: zf.extractall(fr)
    pngs = sorted(fr.glob("*.png"))
    print(f"  {mk}: {len(pngs)} frames")
    for fp in pngs:
        pushf(fp, f"sprites/{mk}/{fp.name}")

print("== prefs: scene_id ==")
xml = runas("cat shared_prefs/pixora_live.xml").stdout
now_ms = int(time.time() * 1000)
base = f"/data/user/0/{PKG}/files/{SID}_master.webp"
def ss(x, n, v):
    p = re.compile(rf'(<string name="{n}">)(.*?)(</string>)', re.S)
    return p.sub(rf'\g<1>{v}\g<3>', x) if p.search(x) else x.replace("</map>", f'    <string name="{n}">{v}</string>\n</map>')
def sl(x, n, v):
    p = re.compile(rf'(<long name="{n}" value=")(\d+)(" />)')
    return p.sub(rf'\g<1>{v}\g<3>', x) if p.search(x) else x.replace("</map>", f'    <long name="{n}" value="{v}" />\n</map>')
xml = ss(xml, "scene_id", SID); xml = ss(xml, "content_id", SID)
xml = ss(xml, "wallpaper_path", base); xml = sl(xml, "changed_at", now_ms)
(TMP / "prefs.xml").write_text(xml, encoding="utf-8")
adb("push", str(TMP / "prefs.xml"), "/data/local/tmp/_pf.xml")
runas("cat /data/local/tmp/_pf.xml > shared_prefs/pixora_live.xml")
print("  scene_id ->", SID)

print("== reiniciar :wallpaper ==")
pid = None
for line in adb("shell", "ps", "-A").stdout.splitlines():
    if f"{PKG}:wallpaper" in line: pid = line.split()[1]; break
if pid: runas(f"kill {pid}"); print("  matado pid", pid)
time.sleep(1)
adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
adb("shell", "input", "keyevent", "KEYCODE_HOME")
print(f"\n[OK] {SID} aplicado en {D}. Mira el device.")
