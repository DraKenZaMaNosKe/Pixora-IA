"""Sube el lote 'Voces de llamada' (20 tonos originales) desde
ia_contenido_pipeline/tonos/1_por_subir/ — audio + imagen + catálogo + FCM.

audio: 1_por_subir/audio/<base>.mp3   →  wallpaper-images/ringtones/<subfolder>/<id>.mp3
imagen: 1_por_subir/imagenes/<base>.png → wallpaper-images/tones/<id>.webp
Empareja audio<->imagen por nombre base. Mergea en packs existentes.
"""
import io, json, re, subprocess, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
CATALOG = "ringtones_catalog.json"
SRC = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/tonos/1_por_subir")
AUD, IMG = SRC / "audio", SRC / "imagenes"
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]

def now_iso(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# base, nombre bonito, pack, tipo, target_seg
R, N = "ringtone", "notification"
AT, MF = "anime_tv_pack", "modern_futuristic_pack"
TONES = [
  ("disculpe_jefe_tiene_una_llamada", "Disculpe jefe, tiene una llamada", AT, R, 12),
  ("japon_arigatou_gozaimasu", "Arigatou Gozaimasu", AT, N, 6),
  ("japon_chakushin_desu", "Chakushin desu (llamada)", AT, R, 12),
  ("japon_moshi_moshi_llamada", "Moshi Moshi", AT, R, 12),
  ("japon_odenwa_goshujinsama", "Odenwa, goshujin-sama", AT, R, 12),
  ("mi_amo_tiene_una_llamada", "Mi amo, tiene una llamada", AT, R, 12),
  ("mi_senor_disculpe_tiene_un_mensaje_anime", "Mi señor, tiene un mensaje", AT, N, 8),
  ("mi_senor_quiere_contestar", "Mi señor, ¿quiere contestar?", AT, R, 12),
  ("mi_senor_tiene_una_llamada", "Mi señor, tiene una llamada", AT, R, 12),
  ("alien_amigo_comunicador", "Comunicador alien amigo", MF, R, 12),
  ("alien_ancestral_transmision", "Transmisión ancestral alien", MF, N, 8),
  ("androide_comunicacion_entrante", "Androide: comunicación entrante", MF, R, 12),
  ("interdimensional_voz_del_vacio", "Voz del vacío interdimensional", MF, N, 8),
  ("llamada_entrante_asistente", "Asistente: llamada entrante", MF, R, 12),
  ("mente_colmena_transmision", "Transmisión mente colmena", MF, N, 8),
  ("protocolo_llamada_activado", "Protocolo de llamada activado", MF, R, 12),
  ("reina_galactica_mi_terricola", "Reina galáctica: mi terrícola", MF, R, 12),
  ("robot_llamada_detectada", "Robot: llamada detectada", MF, R, 12),
  ("robot_mensaje_prioridad", "Robot: mensaje prioridad", MF, N, 6),
  ("traductor_alienigena_llamada", "Traductor alienígena: llamada", MF, R, 12),
]

def put(remote, body, ct):
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}",
                                 data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=120) as r: return r.status

def process_audio(src, dst, target):
    r = subprocess.run(["ffprobe","-v","error","-show_entries","format=duration",
        "-of","default=noprint_wrappers=1:nokey=1", str(src)], capture_output=True, text=True)
    dur = float(r.stdout.strip() or 0)
    actual = min(target, dur) if dur else target
    fade = max(0, actual - 0.2)
    af = f"atrim=0:{actual:.2f},afade=t=out:st={fade:.2f}:d=0.2,loudnorm=I=-16:LRA=11:TP=-1.5"
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",str(src),"-af",af,
        "-ar","44100","-b:a","128k","-codec:a","libmp3lame", str(dst)], check=True)
    return max(1, round(actual))

# catálogo actual
cat = json.loads(urllib.request.urlopen(f"{PROJECT}/storage/v1/object/public/{BUCKET}/{CATALOG}?nc=1", timeout=20).read())
packs = {p["id"]: p for p in cat.get("packs", [])}
OUT = Path(__file__).parent / "out" / "_voces"; OUT.mkdir(parents=True, exist_ok=True)

added = {}
for base, name, pack_id, sug, target in TONES:
    a_src = AUD / f"{base}.mp3"
    i_src = next((IMG / f"{base}{e}" for e in (".png",".jpg",".jpeg",".webp") if (IMG / f"{base}{e}").exists()), None)
    if not a_src.exists():
        print(f"[SKIP] {base}: sin audio"); continue
    tone_id = base
    subf = pack_id.replace("_pack","")
    # audio
    dst = OUT / f"{tone_id}.mp3"
    dsec = process_audio(a_src, dst, target)
    put(f"ringtones/{subf}/{tone_id}.mp3", dst.read_bytes(), "audio/mpeg")
    # imagen
    prev = ""
    if i_src:
        im = Image.open(i_src).convert("RGBA"); im.thumbnail((512,512), Image.LANCZOS)
        buf = io.BytesIO(); im.save(buf, "WEBP", quality=85, method=6)
        put(f"tones/{tone_id}.webp", buf.getvalue(), "image/webp")
        prev = f"tones/{tone_id}.webp"
    entry = {"id": tone_id, "name": name, "file": f"ringtones/{subf}/{tone_id}.mp3",
             "duration": dsec, "suggestedType": sug, "previewImage": prev,
             "addedAt": now_iso(), "source": "voces_2026_07"}
    added.setdefault(pack_id, []).append(entry)
    print(f"  ✓ {tone_id:42} {dsec}s  {pack_id}  img={'sí' if prev else 'NO'}")

# merge
for pid, items in added.items():
    p = packs.get(pid)
    if not p: print(f"[!] pack {pid} no existe"); continue
    ex = {t["id"]: t for t in p.get("tones", [])}
    for t in items: ex[t["id"]] = t
    p["tones"] = list(ex.values())
    print(f"  pack {pid}: +{len(items)} → {len(p['tones'])} tonos")
cat["lastUpdated"] = now_iso()
put(CATALOG, json.dumps(cat, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
print("  catalog subido OK")

# FCM
try:
    sys.path.insert(0, str(Path(__file__).parent.parent / "wallpapers"))
    from _fcm_push import send_catalog_invalidate
    print("  FCM ringtones ->", send_catalog_invalidate("ringtones"))
except Exception as e:
    print("  FCM fallo (no crítico):", e)
print(f"\n[OK] {sum(len(v) for v in added.values())} tonos subidos.")
