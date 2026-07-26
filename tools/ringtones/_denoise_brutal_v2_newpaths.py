"""Toma los 22 tonos v02 de Codex (1_por_subir/audio/<id>_version_02.mp3),
les aplica el denoise BRUTAL (spectral gating x2) y los sube a RUTAS NUEVAS
(ringtones/voces_llamada_v2/<id>.mp3) para romper el caché del device.
Actualiza el catálogo (file -> nueva ruta + duration) + FCM.

Imágenes: se mantienen las actuales (Codex no mandó nuevas).
"""
import json, re, subprocess, sys, urllib.request
import numpy as np
from datetime import datetime, timezone
from pathlib import Path
from scipy.io import wavfile
from scipy.signal import stft, istft
from scipy.ndimage import uniform_filter

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
PROJECT = "https://vzuwvsmlyigjtsearxym.supabase.co"
BUCKET = "wallpaper-images"
CATALOG = "ringtones_catalog.json"
PACK_ID = "voces_llamada_pack"
NEWDIR = "ringtones/voces_llamada_v2"   # ruta nueva -> URL nueva -> sin caché viejo
SRCDIR = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/tonos/1_por_subir/audio")
CLEANDIR = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/tonos/3_publicados/voces_llamada_2026_07/audio_LIMPIO_v2")
CLEANDIR.mkdir(parents=True, exist_ok=True)
TMP = Path(__file__).parent / "out" / "_brutalv2"; TMP.mkdir(parents=True, exist_ok=True)
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]
OVER, FLOOR, PCT, PASSES = 2.8, 0.02, 25, 2

def now_iso(): return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def put(remote, body, ct):
    req = urllib.request.Request(f"{PROJECT}/storage/v1/object/{BUCKET}/{remote}", data=body, method="PUT")
    req.add_header("Authorization", f"Bearer {SK}"); req.add_header("apikey", SK)
    req.add_header("Content-Type", ct); req.add_header("x-upsert", "true")
    req.add_header("Cache-Control", "no-cache, max-age=0")
    with urllib.request.urlopen(req, timeout=120) as r: return r.status

def gate(x, sr):
    for _ in range(PASSES):
        f, tt, Z = stft(x, fs=sr, nperseg=2048, noverlap=1536)
        mag = np.abs(Z); ph = np.angle(Z)
        noise = np.percentile(mag, PCT, axis=1, keepdims=True)
        mask = np.clip((mag - OVER * noise) / (mag + 1e-9), FLOOR, 1.0)
        mask = uniform_filter(mask, size=(2, 3))
        _, x = istft(mag * mask * np.exp(1j * ph), fs=sr, nperseg=2048, noverlap=1536)
    return x

def clean(src_mp3, out_mp3):
    wi = TMP / "in.wav"; wo = TMP / "out.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src_mp3), "-ar", "44100", str(wi)], check=True)
    sr, data = wavfile.read(wi); data = data.astype(np.float32) / 32768.0
    if data.ndim == 1: data = data[:, None]
    chs = [gate(data[:, c], sr) for c in range(data.shape[1])]
    L = min(map(len, chs)); out = np.clip(np.stack([c[:L] for c in chs], axis=1), -1, 1)
    wavfile.write(wo, sr, (out * 32768).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wo), "-ar", "44100",
                    "-b:a", "128k", "-codec:a", "libmp3lame", str(out_mp3)], check=True)

def floor_of(f):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(f), "-af", "astats=metadata=1", "-f", "null", "-"],
                       capture_output=True, text=True)
    n = [l for l in r.stderr.splitlines() if "Noise floor dB" in l]
    return n[0].split(":")[-1].strip() if n else "?"

def dur_of(f):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(f)], capture_output=True, text=True)
    return max(1, round(float(r.stdout.strip() or 0)))

cat = json.loads(urllib.request.urlopen(
    f"{PROJECT}/storage/v1/object/public/{BUCKET}/{CATALOG}?nc=1", timeout=20).read())
pack = next(p for p in cat["packs"] if p["id"] == PACK_ID)
byid = {t["id"]: t for t in pack["tones"]}

done, missing = 0, []
for src in sorted(SRCDIR.glob("*_version_02.mp3")):
    tid = src.name.replace("_version_02.mp3", "")
    t = byid.get(tid)
    if not t:
        missing.append(tid); continue
    cm = CLEANDIR / f"{tid}.mp3"
    clean(src, cm)
    remote = f"{NEWDIR}/{tid}.mp3"
    put(remote, cm.read_bytes(), "audio/mpeg")
    t["file"] = remote
    t["duration"] = dur_of(cm)
    done += 1
    print(f"  ✓ {tid:42} floor={floor_of(cm):<10} -> {remote}")

if missing:
    print("  [!] sin match en catálogo:", missing)
cat["lastUpdated"] = now_iso()
put(CATALOG, json.dumps(cat, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"\n[OK] {done} tonos limpios subidos a RUTA NUEVA + catálogo actualizado.")

try:
    sys.path.insert(0, str(Path(__file__).parent.parent / "wallpapers"))
    from _fcm_push import send_catalog_invalidate
    print("FCM ringtones ->", send_catalog_invalidate("ringtones"))
except Exception as e:
    print("FCM fallo (no crítico):", e)
