#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out/nature
DUR=900
SR=48000
BR=192k

# White noise
ffmpeg -y -f lavfi -i "anoisesrc=color=white:sample_rate=${SR}:duration=${DUR}:amplitude=0.3" \
  -af "afade=t=in:st=0:d=3,afade=t=out:st=$((DUR-3)):d=3,loudnorm=I=-18:TP=-2:LRA=7" \
  -c:a libmp3lame -b:a ${BR} out/nature/white_noise.mp3 -loglevel error
echo ">> white_noise.mp3"

# Brown noise
ffmpeg -y -f lavfi -i "anoisesrc=color=brown:sample_rate=${SR}:duration=${DUR}:amplitude=0.5" \
  -af "afade=t=in:st=0:d=3,afade=t=out:st=$((DUR-3)):d=3,loudnorm=I=-18:TP=-2:LRA=7" \
  -c:a libmp3lame -b:a ${BR} out/nature/brown_noise.mp3 -loglevel error
echo ">> brown_noise.mp3"
