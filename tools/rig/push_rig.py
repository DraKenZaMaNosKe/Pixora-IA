"""Empuja la escena del rig al Samsung por cable (run-as, app debug) y la
activa cambiando scene_id en las prefs pixora_live + reiniciando el wallpaper.
No toca Supabase. Solo este device.
"""
import subprocess, sys, time, re
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
D = "RF8X903KZ3K"
PKG = "com.orbix.pixora"
SCENE = "heroina_candy_mecha_rig_v1"
STAGE = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/heroina_candy_mecha_rig_v1/rig_parts/device_staging")

def sh(*args, check=True):
    r = subprocess.run(["adb", "-s", D, *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        print("ERR:", " ".join(args), "\n", r.stderr.strip())
    return r

def runas(cmd):
    # ejecuta un comando shell como el uid de la app (app debug)
    return subprocess.run(["adb", "-s", D, "shell", f"run-as {PKG} sh -c '{cmd}'"],
                          capture_output=True, text=True)

def push_file(local: Path, dest_rel: str):
    """dest_rel relativo a files/ de la app. Two-step: push a /data/local/tmp -> cat a files/."""
    tmp = "/data/local/tmp/_rigpush.bin"
    sh("push", str(local), tmp)
    d = dest_rel.rsplit("/", 1)[0] if "/" in dest_rel else ""
    if d:
        runas(f"mkdir -p files/{d}")
    r = runas(f"cat {tmp} > files/{dest_rel}")
    if r.returncode != 0:
        print("  cat ERR:", dest_rel, r.stderr.strip())
    # verificar tamaño
    sz = runas(f"stat -c %s files/{dest_rel}").stdout.strip()
    print(f"  ✓ files/{dest_rel}  ({sz} bytes vs {local.stat().st_size} local)")

# 1) empujar todos los archivos del staging
print("== empujando assets ==")
mapping = {
    "scene_specs/heroina_candy_mecha_rig_v1.json": "scene_specs/heroina_candy_mecha_rig_v1.json",
    "scene_layers/heroina_candy_mecha_rig_v1/bg.webp": "scene_layers/heroina_candy_mecha_rig_v1/bg.webp",
    "heroina_master.webp": "heroina_master.webp",
}
for part in ("arm", "head", "leg_bent", "leg_up", "torso"):
    mapping[f"sprites/rigs/heroina_v1/{part}/frame_001.png"] = f"sprites/rigs/heroina_v1/{part}/frame_001.png"
for rel, dest in mapping.items():
    local = STAGE / rel
    if not local.is_file():
        print("  [!] falta local:", rel); continue
    push_file(local, dest)

# 2) matar el proceso para liberar el XML de prefs
print("== force-stop (libera prefs) ==")
sh("shell", "am", "force-stop", PKG)
time.sleep(1.5)

# 3) leer + modificar pixora_live.xml preservando las demás claves
print("== editando prefs pixora_live.xml ==")
xml = runas("cat shared_prefs/pixora_live.xml").stdout
if "<map" not in xml:
    print("  [!] no pude leer el XML actual:\n", xml[:200]); sys.exit(1)
now_ms = int(time.time() * 1000)
base = f"/data/user/0/{PKG}/files/heroina_master.webp"

def set_string(x, name, val):
    pat = re.compile(rf'(<string name="{name}">)(.*?)(</string>)', re.S)
    if pat.search(x):
        return pat.sub(rf'\g<1>{val}\g<3>', x)
    return x.replace("</map>", f'    <string name="{name}">{val}</string>\n</map>')

def set_long(x, name, val):
    pat = re.compile(rf'(<long name="{name}" value=")(\d+)(" />)')
    if pat.search(x):
        return pat.sub(rf'\g<1>{val}\g<3>', x)
    return x.replace("</map>", f'    <long name="{name}" value="{val}" />\n</map>')

xml = set_string(xml, "scene_id", SCENE)
xml = set_string(xml, "content_id", SCENE)
xml = set_string(xml, "wallpaper_path", base)
xml = set_long(xml, "changed_at", now_ms)

# escribir de vuelta
tmp = "/data/local/tmp/_prefs.xml"
Path("_prefs_tmp.xml").write_text(xml, encoding="utf-8")
sh("push", "_prefs_tmp.xml", tmp)
runas(f"cat {tmp} > shared_prefs/pixora_live.xml")
Path("_prefs_tmp.xml").unlink(missing_ok=True)
print("  scene_id ->", SCENE)
print(runas("cat shared_prefs/pixora_live.xml").stdout)

# 4) reactivar el wallpaper: home + wake para forzar respawn del service
print("== reiniciando wallpaper ==")
sh("shell", "input", "keyevent", "KEYCODE_WAKEUP")
sh("shell", "am", "start", "-a", "android.intent.action.MAIN", "-c", "android.intent.category.HOME")
print("\n[OK] listo. Mira tu Samsung — debería cargar la heroína riggeada en unos segundos.")
print("Si ves la escena vieja, desbloquea/bloquea una vez para forzar el redraw.")
