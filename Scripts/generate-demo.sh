#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Original generated tones, solely for smoke testing. No commercial audio.
set -euo pipefail
cd "${0:A:h:h}"
out="${1:-build/Demo Album}"
mkdir -p "$out"
for number in 1 2 3; do
  ffmpeg -nostdin -v error -y -f lavfi -i "sine=frequency=$((220 * number)):sample_rate=44100:duration=5" \
    -ac 2 -c:a flac -sample_fmt s16 -metadata TITLE="Test tone $number" \
    -metadata ARTIST="CDScribe Test Ensemble" -metadata ALBUM="A Disc of Our Own" \
    -metadata ALBUMARTIST="CDScribe Test Ensemble" -metadata TRACKNUMBER="$number/3" \
    -metadata DISCNUMBER="1/1" "$out/0$number.flac"
done
print "Import this folder in CDScribe: $out"
