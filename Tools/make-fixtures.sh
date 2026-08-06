#!/bin/zsh
# Generates the audio-verify test corpus (SPEC §4.6): 1 kHz sine and white
# noise at six sample rates, 16 and 24 bit, stereo FLAC. Files land in
# Fixtures/ (gitignored). Requires ffmpeg.
#
# ponytail: DSD64 fixture is NOT generated — ffmpeg has no DSF muxer.
# DSD is verified manually on real DSF files (docs/manual-checklist.md).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=Fixtures
DURATION=5
mkdir -p "$OUT"

command -v ffmpeg >/dev/null || { echo "ffmpeg not found — brew install ffmpeg" >&2; exit 1 }

for rate in 44100 48000 88200 96000 176400 192000; do
    for bits in 16 24; do
        # FLAC has no s24 sample_fmt in ffmpeg: 24-bit rides in s32 frames
        # with bits_per_raw_sample=24.
        if [[ $bits == 16 ]]; then
            fmt_args=(-sample_fmt s16)
        else
            fmt_args=(-sample_fmt s32 -bits_per_raw_sample 24)
        fi
        # 1 kHz sine, -6 dBFS
        ffmpeg -loglevel error -y -f lavfi \
            -i "sine=frequency=1000:duration=${DURATION}:sample_rate=${rate},volume=0.5,aformat=channel_layouts=stereo" \
            -c:a flac "${fmt_args[@]}" "$OUT/sine-${rate}-${bits}.flac"
        # white noise, -12 dBFS, fixed seed for reproducibility
        ffmpeg -loglevel error -y -f lavfi \
            -i "anoisesrc=colour=white:duration=${DURATION}:sample_rate=${rate}:seed=42:amplitude=0.25,aformat=channel_layouts=stereo" \
            -c:a flac "${fmt_args[@]}" "$OUT/noise-${rate}-${bits}.flac"
    done
done

ls -la "$OUT" | tail -n +2 | wc -l | xargs echo "fixtures:"
