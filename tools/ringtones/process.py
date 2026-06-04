"""
Process raw ringtones into clean, ready-to-ship MP3s.

For each raw file:
  1. Trim leading/trailing silence
  2. Cut to target_sec (from manifest)
  3. Apply small fade in (10ms) + fade out (50ms) to prevent clicks
  4. Normalize loudness to -16 LUFS (slightly louder than AURA's -18,
     since ringtones need to be heard over ambient noise)
  5. Encode 192k MP3 to out/<pack>/<id>.mp3

Skips files that don't exist in raw/.
"""
import io
import json
import subprocess
import sys
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "manifest.json"
RAW = ROOT / "raw"
OUT = ROOT / "out"


def ffprobe_duration(p: Path) -> float:
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nokey=1:noprint_wrappers=1", str(p)],
        capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def process(pack_id: str, tone: dict) -> bool:
    raw = RAW / pack_id / f"{tone['id']}.mp3"
    out = OUT / pack_id / f"{tone['id']}.mp3"
    out.parent.mkdir(parents=True, exist_ok=True)

    if not raw.exists():
        print(f"!! missing raw for {tone['id']}")
        return False

    target = float(tone.get("target_sec", 3))
    src_dur = ffprobe_duration(raw)
    actual = min(target, src_dur)
    fade_out_start = max(0.0, actual - 0.05)

    # ffmpeg filter chain:
    #   silenceremove → strip leading silence
    #   atrim → cut to target duration
    #   afade in 10ms + out 50ms
    #   loudnorm → broadcast-loud level
    filter_chain = (
        f"silenceremove=start_periods=1:start_silence=0.05:start_threshold=-50dB,"
        f"atrim=0:{actual:.3f},"
        f"afade=t=in:st=0:d=0.01,"
        f"afade=t=out:st={fade_out_start:.3f}:d=0.05,"
        f"loudnorm=I=-16:LRA=11:TP=-1.5"
    )

    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(raw),
        "-af", filter_chain,
        "-c:a", "libmp3lame", "-b:a", "192k",
        str(out),
    ]
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"!! ffmpeg failed for {tone['id']}: {e}")
        return False

    final_dur = ffprobe_duration(out)
    print(f"  ok {tone['id']:30} | {src_dur:5.1f}s -> {final_dur:4.1f}s | {out.stat().st_size//1024} KB")
    return True


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    total = ok = 0
    for pack in manifest["packs"]:
        print(f"\n═══ {pack['name']} ═══")
        for t in pack["tones"]:
            total += 1
            if process(pack["id"], t):
                ok += 1
    print(f"\nDone. {ok}/{total} processed → {OUT}")


if __name__ == "__main__":
    main()
