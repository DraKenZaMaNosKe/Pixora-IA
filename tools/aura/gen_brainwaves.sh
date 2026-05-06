#!/usr/bin/env bash
# Wave 1 — brainwave binaural beats + pink noise
# Generates left+right channel sine waves with a delta to create the binaural
# perception of the target frequency in the listener's brain.
#
# Carrier 200Hz left, 200+target Hz right → perceived "beat" = target.
# Standard practice in commercial brainwave entrainment audio.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out/frequencies
DUR=900       # 15 minutes
FADE=5
SR=48000
BR=192k
CARRIER=200   # left-ear carrier in Hz

# target_hz : slug : marketing_name
declare -a BRAINWAVES=(
  "2.5:delta:Deep Sleep · Delta 2.5Hz"
  "6:theta:Meditation · Theta 6Hz"
  "7.83:schumann:Earth Resonance · Schumann 7.83Hz"
  "10:alpha:Relaxed Awake · Alpha 10Hz"
  "40:gamma:Peak Focus · Gamma 40Hz"
)

echo "=== Generating 5 binaural brainwave tracks ==="
for entry in "${BRAINWAVES[@]}"; do
  hz="${entry%%:*}"
  rest="${entry#*:}"
  slug="${rest%%:*}"
  out="out/frequencies/brainwave_${slug}_${hz}hz.mp3"
  right=$(awk "BEGIN{print ${CARRIER}+${hz}}")
  echo ">> ${slug} ${hz}Hz (carrier ${CARRIER}/${right}Hz) -> ${out}"
  ffmpeg -y \
    -f lavfi -i "sine=frequency=${CARRIER}:sample_rate=${SR}:duration=${DUR}" \
    -f lavfi -i "sine=frequency=${right}:sample_rate=${SR}:duration=${DUR}" \
    -filter_complex "[0:a]aformat=channel_layouts=mono[L];[1:a]aformat=channel_layouts=mono[R];[L][R]amerge=inputs=2[stereo];[stereo]volume=0.4,afade=t=in:st=0:d=${FADE},afade=t=out:st=$((DUR-FADE)):d=${FADE},loudnorm=I=-18:TP=-2:LRA=7[a]" \
    -map "[a]" -ac 2 \
    -c:a libmp3lame -b:a ${BR} \
    "${out}" -loglevel error
done

echo ""
echo "=== Generating Pink Noise ==="
out="out/frequencies/pink_noise.mp3"
echo ">> pink_noise -> ${out}"
ffmpeg -y \
  -f lavfi -i "anoisesrc=color=pink:sample_rate=${SR}:duration=${DUR}" \
  -af "volume=0.5,afade=t=in:st=0:d=${FADE},afade=t=out:st=$((DUR-FADE)):d=${FADE},loudnorm=I=-18:TP=-2:LRA=7" \
  -ac 2 \
  -c:a libmp3lame -b:a ${BR} \
  "${out}" -loglevel error

echo ""
echo "Done. 5 brainwaves + 1 pink noise = 6 new tracks in out/frequencies/"
ls -lh out/frequencies/brainwave_*.mp3 out/frequencies/pink_noise.mp3 2>&1 | tail -10
