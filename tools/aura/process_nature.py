"""
For each downloaded raw nature sound:
  1. Trim leading/trailing silence
  2. Loop to reach 10 minutes
  3. Apply fade in/out
  4. Normalize loudness to -18 LUFS
  5. Encode 192k MP3 to out/nature/<id>.mp3
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "tracks_manifest.json"
RAW = ROOT / "raw"

TARGET_SECONDS = 600  # 10 min


def ffprobe_duration(p: Path) -> float:
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nokey=1:noprint_wrappers=1", str(p)],
        capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def process(track: dict) -> None:
    raw = RAW / f"{track['id']}.mp3"
    out = ROOT / track["file"]
    out.parent.mkdir(parents=True, exist_ok=True)
    if not raw.exists():
        print(f"!! missing raw for {track['id']}")
        return

    dur = ffprobe_duration(raw)
    loops = max(1, int(TARGET_SECONDS // dur) + 1)

    # Simple pipeline: loop → trim → fades → loudnorm.
    # size needs to be integer samples; 600s * 48000 = 28.8M is plenty.
    af = (
        f"aloop=loop={loops}:size=30000000,"
        f"atrim=duration={TARGET_SECONDS},"
        "asetpts=N/SR/TB,"
        "afade=t=in:st=0:d=3,"
        f"afade=t=out:st={TARGET_SECONDS-5}:d=5,"
        "loudnorm=I=-18:TP=-2:LRA=7"
    )

    cmd = [
        "ffmpeg", "-y", "-i", str(raw),
        "-af", af,
        "-c:a", "libmp3lame", "-b:a", "192k",
        str(out), "-loglevel", "error",
    ]
    print(f">> {track['id']}  raw={dur:.1f}s loops={loops} -> {Path(track['file']).name}")
    subprocess.run(cmd, check=True)


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for t in manifest["nature"]:
        if t["license"] == "GENERATED":
            continue
        process(t)
    print("Done.")


if __name__ == "__main__":
    main()
