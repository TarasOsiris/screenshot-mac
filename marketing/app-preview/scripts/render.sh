#!/bin/sh
# Renders the three App Store app previews (30 fps, H.264 + AAC stereo 48 kHz, ≤30 s):
# out/app-preview-iphone.mp4 (886x1920), out/app-preview-ipad.mp4 (1600x1200),
# out/app-preview-mac.mp4 (1920x1080).
set -e
cd "$(dirname "$0")/.."
[ -f public/audio/soundtrack.wav ] || npm run assets
for pair in AppPreview:iphone iPadPreview:ipad MacPreview:mac; do
  comp=${pair%%:*}
  name=${pair##*:}
  npx remotion render src/index.ts "$comp" "out/$comp.raw.mp4" --codec=h264 --crf=16 --audio-bitrate=256k --log=error
  ffmpeg -v error -y -i "out/$comp.raw.mp4" -c:v libx264 -profile:v high -level 4.2 -pix_fmt yuv420p -crf 16 -r 30 \
    -c:a aac -b:a 256k -ar 48000 -ac 2 -movflags +faststart "out/app-preview-$name.mp4"
  rm "out/$comp.raw.mp4"
done
ls -lh out/*.mp4
