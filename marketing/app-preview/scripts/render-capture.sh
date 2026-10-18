#!/bin/sh
# Renders the screen-capture App Store previews from public/capture/*.mp4 (cut from simulator / window
# recordings): out/app-preview-{iphone,ipad,mac}-capture.mp4, 30 fps, H.264 + AAC stereo 48 kHz.
set -e
cd "$(dirname "$0")/.."
[ -f public/audio/soundtrack.wav ] || npm run assets
for pair in iPhoneCapture:iphone iPadCapture:ipad MacCapture:mac; do
  comp=${pair%%:*}
  name=${pair##*:}
  npx remotion render src/index.ts "$comp" "out/$comp.raw.mp4" --codec=h264 --crf=16 --log=error
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "out/$comp.raw.mp4")
  fade=$(echo "$dur - 1.4" | bc)
  ffmpeg -v error -y -i "out/$comp.raw.mp4" -i public/audio/soundtrack.wav \
    -filter_complex "[1:a]atrim=0:$dur,afade=t=in:d=0.3,afade=t=out:st=$fade:d=1.4,volume=0.8[a]" \
    -map 0:v -map "[a]" -c:v libx264 -profile:v high -level 4.2 -pix_fmt yuv420p -crf 16 -r 30 \
    -c:a aac -b:a 256k -ar 48000 -ac 2 -shortest -movflags +faststart "out/app-preview-$name-capture.mp4"
  rm "out/$comp.raw.mp4"
done
ls -lh out/*-capture.mp4
