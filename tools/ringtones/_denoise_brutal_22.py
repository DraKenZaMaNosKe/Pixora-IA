"""Aplica el denoise 'BRUTAL' (spectral gating, 2 pasadas) a los 22 tonos de
Voces de Llamada y los re-sube EN SU RUTA ACTUAL (upsert) + FCM.

Fuente: los originales de Codex en 3_publicados/voces_llamada_2026_07/audio/.
Deja copia de los limpios en .../audio_LIMPIO/ (respaldo).
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
SRCDIR = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/tonos/3_publicados/voces_llamada_2026_07/audio")
CLEANDIR = SRCDIR.parent / "audio_LIMPIO"; CLEANDIR.mkdir(exist_ok=True)
TMP = Path(__file__).parent / "out" / "_brutal"; TMP.mkdir(parents=True, exist_ok=True)
SK = re.findall(r"eyJ[A-Za-z0-9_\-\.]{100,500}",
                Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md").read_text(encoding="utf-8"))[0]

# receta BRUTAL aprobada por Eduardo
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

def clean(src_mp3, clean_mp3):
    wav_in = TMP / "in.wav"; wav_out = TMP / "out.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src_mp3), "-ar", "44100", str(wav_in)], check=True)
    sr, data = wavfile.read(wav_in); data = data.astype(np.float32) / 32768.0
    if data.ndim == 1: data = data[:, None]
    chs = [gate(data[:, c], sr) for c in range(data.shape[1])]
    L = min(map(len, chs)); out = np.clip(np.stack([c[:L] for c in chs], axis=1), -1, 1)
    wavfile.write(wav_out, sr, (out * 32768).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_out), "-ar", "44100",
                    "-b:a", "128k", "-codec:a", "libmp3lame", str(clean_mp3)], check=True)

def dur_of(f):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(f)], capture_output=True, text=True)
    return max(1, round(float(r.stdout.strip() or 0)))

cat = json.loads(urllib.request.urlopen(
    f"{PROJECT}/storage/v1/object/public/{BUCKET}/{CATALOG}?nc=1", timeout=20).read())
pack = next(p for p in cat["packs"] if p["id"] == PACK_ID)

done = 0
for t in pack["tones"]:
    tid = t["id"]; src = SRCDIR / f"{tid}.mp3"
    if not src.exists():
        print(f"  [SKIP] sin fuente: {tid}"); continue
    cm = CLEANDIR / f"{tid}.mp3"
    clean(src, cm)
    put(t["file"], cm.read_bytes(), "audio/mpeg")
    t["duration"] = dur_of(cm)
    done += 1
    print(f"  ✓ {tid:42} {t['duration']:>3}s -> {t['file']}")

cat["lastUpdated"] = now_iso()
put(CATALOG, json.dumps(cat, indent=2, ensure_ascii=False).encode("utf-8"), "application/json")
print(f"\n[OK] {done} tonos denoised (BRUTAL) y re-subidos.")

try:
    sys.path.insert(0, str(Path(__file__).parent.parent / "wallpapers"))
    from _fcm_push import send_catalog_invalidate
    print("FCM ringtones ->", send_catalog_invalidate("ringtones"))
except Exception as e:
    print("FCM fallo (no crítico):", e)
