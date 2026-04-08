#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out/frequencies
DUR=900       # 15 minutes
FADE=5        # 5 second fade
SR=48000
BR=192k

declare -a TRACKS=(
  "174:foundation"
  "285:quantum"
  "396:liberation"
  "417:transmutation"
  "528:miracle"
  "639:connection"
  "741:expression"
  "852:intuition"
  "963:divine"
)

for pair in "${TRACKS[@]}"; do
  hz="${pair%%:*}"
  name="${pair##*:}"
  out="out/frequencies/${hz}hz_${name}.mp3"
  echo ">> ${hz}Hz -> ${out}"
  ffmpeg -y \
    -f lavfi -i "sine=frequency=${hz}:sample_rate=${SR}:duration=${DUR}" \
    -af "afade=t=in:st=0:d=${FADE},afade=t=out:st=$((DUR-FADE)):d=${FADE},volume=0.5,loudnorm=I=-18:TP=-2:LRA=7" \
    -c:a libmp3lame -b:a ${BR} \
    "${out}" -loglevel error
done
echo "Done. 9 frequencies generated."
