"""Cambia la escena activa del wallpaper Pixora a la del rig, SIN force-stop:
edita scene_id en prefs y reinicia SOLO el proceso :wallpaper (kill por pid,
mismo uid via run-as). El sistema lo respawnea con la escena nueva.
"""
import subprocess, sys, time, re
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
D = "RF8X903KZ3K"
PKG = "com.orbix.pixora"
SCENE = "heroina_candy_mecha_rig_v1"

def adb(*a):
    return subprocess.run(["adb", "-s", D, *a], capture_output=True, text=True)

def runas(cmd):
    return subprocess.run(["adb", "-s", D, "shell", f"run-as {PKG} sh -c '{cmd}'"],
                          capture_output=True, text=True)

# 1) editar prefs (preservando las demás claves)
xml = runas("cat shared_prefs/pixora_live.xml").stdout
if "<map" not in xml:
    print("[!] no pude leer prefs:\n", xml[:200]); sys.exit(1)
now_ms = int(time.time() * 1000)
base = f"/data/user/0/{PKG}/files/heroina_master.webp"

def set_string(x, name, val):
    pat = re.compile(rf'(<string name="{name}">)(.*?)(</string>)', re.S)
    return pat.sub(rf'\g<1>{val}\g<3>', x) if pat.search(x) else \
        x.replace("</map>", f'    <string name="{name}">{val}</string>\n</map>')

def set_long(x, name, val):
    pat = re.compile(rf'(<long name="{name}" value=")(\d+)(" />)')
    return pat.sub(rf'\g<1>{val}\g<3>', x) if pat.search(x) else \
        x.replace("</map>", f'    <long name="{name}" value="{val}" />\n</map>')

xml = set_string(xml, "scene_id", SCENE)
xml = set_string(xml, "content_id", SCENE)
xml = set_string(xml, "wallpaper_path", base)
xml = set_long(xml, "changed_at", now_ms)

tmp = "/data/local/tmp/_prefs.xml"
Path("_prefs_tmp.xml").write_text(xml, encoding="utf-8")
adb("push", "_prefs_tmp.xml", tmp)
runas(f"cat {tmp} > shared_prefs/pixora_live.xml")
Path("_prefs_tmp.xml").unlink(missing_ok=True)
print("prefs -> scene_id =", SCENE)

# 2) matar SOLO el proceso :wallpaper (por pid, sin force-stop)
ps = adb("shell", "ps", "-A").stdout
pid = None
for line in ps.splitlines():
    if f"{PKG}:wallpaper" in line:
        pid = line.split()[1]; break
if pid:
    print("matando :wallpaper pid", pid, "(respawnea con la escena nueva)")
    runas(f"kill {pid}")
else:
    print("[!] no encontré el proceso :wallpaper; puede que ya no corra")

# 3) despertar + home para forzar el respawn/redraw
time.sleep(1.0)
adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
adb("shell", "input", "keyevent", "KEYCODE_HOME")
print("\n[OK] mira tu Samsung — debe cargar la heroína riggeada.")
