"""Sube los 22 tonos regenerados por Codex (voces + románticas) al pack
'voces_llamada_pack'. Reemplaza los 20 existentes EN SU RUTA ACTUAL (upsert)
y agrega las 2 románticas nuevas.

Respeta el trabajo de Codex: NO re-corta ni re-aplica fade; solo pasa un
loudnorm para emparejar el volumen con el resto del catálogo (misma norma
I=-16 que ya tienen Zelda/Gaming/etc.).
"""
import io, json, re, subprocess, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
CATALOG = "ringtones_catalog.json"
PACK_ID = "voces_llamada_pack"
SRC = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/tonos/1_por_subir")
AUD, IMG = SRC / "audio", SRC / "imagenes"
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]

# tonos NUEVOS (no existen aún en el pack) → nombre bonito + tipo
NEW_META = {
    "mi_amor_tienes_una_llamada": ("Mi amor, tienes una llamada", "ringtone"),
    "mi_amor_es_un_mensaje_bebe": ("Mi amor, es un mensaje, bebé", "notification"),
}

def now_iso(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def put(remote, body, ct):
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=120) as r: return r.status

def loudnorm(src, dst):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src),
        "-af", "loudnorm=I=-16:LRA=11:TP=-1.5", "-ar", "44100", "-b:a", "128k",
        "-codec:a", "libmp3lame", str(dst)], check=True)

def dur_of(f):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(f)], capture_output=True, text=True)
    return max(1, round(float(r.stdout.strip() or 0)))

cat = json.loads(urllib.request.urlopen(
    f"{PROJECT}/storage/v1/object/public/{BUCKET}/{CATALOG}?nc=1", timeout=20).read())
pack = next((p for p in cat["packs"] if p["id"] == PACK_ID), None)
assert pack, "pack voces_llamada_pack no existe"
existing = {t["id"]: t for t in pack["tones"]}
OUT = Path(__file__).parent / "out" / "_final22"; OUT.mkdir(parents=True, exist_ok=True)

count = 0
for a in sorted(AUD.glob("*.mp3")):
    tid = a.stem
    i_src = next((IMG / f"{tid}{e}" for e in (".png", ".jpg", ".jpeg", ".webp")
                  if (IMG / f"{tid}{e}").exists()), None)
    remote_audio = existing[tid]["file"] if tid in existing else f"ringtones/voces_llamada/{tid}.mp3"
    dst = OUT / f"{tid}.mp3"; loudnorm(a, dst); dsec = dur_of(dst)
    put(remote_audio, dst.read_bytes(), "audio/mpeg")
    prev = existing.get(tid, {}).get("previewImage", f"tones/{tid}.webp")
    if i_src:
        im = Image.open(i_src).convert("RGBA"); im.thumbnail((512, 512), Image.LANCZOS)
        buf = io.BytesIO(); im.save(buf, "WEBP", quality=85, method=6)
        put(f"tones/{tid}.webp", buf.getvalue(), "image/webp"); prev = f"tones/{tid}.webp"
    if tid in existing:
        existing[tid]["duration"] = dsec
        existing[tid]["previewImage"] = prev
    else:
        name, typ = NEW_META.get(tid, (tid.replace("_", " ").capitalize(), "notification"))
        entry = {"id": tid, "name": name, "file": remote_audio, "duration": dsec,
                 "suggestedType": typ, "previewImage": prev,
                 "addedAt": now_iso(), "source": "romance_2026_07"}
        pack["tones"].append(entry); existing[tid] = entry
    count += 1
    tag = "NUEVO" if tid in NEW_META else "upd"
    print(f"  ✓ [{tag:5}] {tid:42} {dsec:>3}s")

cat["lastUpdated"] = now_iso()
put(CATALOG, json.dumps(cat, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"\n[OK] {count} tonos procesados · '{pack['name']}' ahora tiene {len(pack['tones'])} tonos.")

try:
    sys.path.insert(0, str(Path(__file__).parent.parent / "wallpapers"))
    from _fcm_push import send_catalog_invalidate
    print("FCM ringtones ->", send_catalog_invalidate("ringtones"))
except Exception as e:
    print("FCM fallo (no crítico):", e)
