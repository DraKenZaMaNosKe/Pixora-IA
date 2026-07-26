"""Aplica una escena rig en el Samsung por cable (sin Supabase visible): baja
spec/bg/flat de Storage, copia las partes del staging local, setea scene_id en
prefs y reinicia SOLO el proceso :wallpaper (kill por pid, NO force-stop).

Uso: python push_scene_to_device.py <SID> <rig_dir> <staging_dir>
"""
import subprocess, sys, time, re, urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
D = "RF8X903KZ3K"; PKG = "com.orbix.pixora"
PUB = "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public"
SID = sys.argv[1]; RIG_DIR = sys.argv[2]; STAGE = Path(sys.argv[3])
TMP = Path("_pushtmp"); TMP.mkdir(exist_ok=True)

def dl(url, dst):
    open(dst, "wb").write(urllib.request.urlopen(f"{url}?nc={int(time.time())}", timeout=40).read())

def adb(*a): return subprocess.run(["adb", "-s", D, *a], capture_output=True, text=True)
def runas(cmd): return subprocess.run(["adb", "-s", D, "shell", f"run-as {PKG} sh -c '{cmd}'"], capture_output=True, text=True)

def pushf(local, dest):
    adb("push", str(local), "/data/local/tmp/_p.bin")
    d = dest.rsplit("/", 1)[0] if "/" in dest else ""
    if d: runas(f"mkdir -p files/{d}")
    r = runas(f"cat /data/local/tmp/_p.bin > files/{dest}")
    ok = r.returncode == 0
    print(f"  {'✓' if ok else '✗'} files/{dest}")

# reconnect
subprocess.run(["adb", "reconnect", "offline"], capture_output=True); time.sleep(2)
if adb("shell", "true").returncode != 0:
    subprocess.run(["adb", "kill-server"]); time.sleep(1); subprocess.run(["adb", "start-server"]); time.sleep(2)

print(f"== bajando assets de {SID} ==")
dl(f"{PUB}/wallpaper-scenes/{SID}.json", TMP / "spec.json")
dl(f"{PUB}/wallpaper-images/{SID}_bg.webp", TMP / "bg.webp")
dl(f"{PUB}/wallpaper-images/{SID}.webp", TMP / "master.webp")

print("== empujando al device ==")
pushf(TMP / "spec.json", f"scene_specs/{SID}.json")
pushf(TMP / "bg.webp", f"scene_layers/{SID}/bg.webp")
pushf(TMP / "master.webp", f"{SID}_master.webp")
for pd in sorted((STAGE / "sprites" / RIG_DIR).iterdir()):
    if pd.is_dir():
        pushf(pd / "frame_001.png", f"sprites/{RIG_DIR}/{pd.name}/frame_001.png")

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
print(f"\n[OK] {SID} aplicado. Mira el Samsung.")
