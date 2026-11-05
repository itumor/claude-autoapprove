#!/bin/bash
# Build docs/media/autoapprove-promo.mp4 (with audio, + demo.gif) from rendered scenes and a screen recording.
#   tools/make-video.sh <screen-recording.mov> [footage-seconds]
# Needs: ffmpeg. Renders scenes first (swift app/make-video.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
REC="${1:?usage: tools/make-video.sh <screen-recording.mov> [footage-seconds]}"
TARGET="${2:-16}"            # seconds the footage occupies after speed-up
V=build/video; OUT=docs/media
mkdir -p "$V/seg" "$OUT"

[[ -f $V/s1/0000.png ]] || swift app/make-video.swift

enc=(-c:v libx264 -pix_fmt yuv420p -preset slow -crf 22 -r 30)
fade() { echo "fade=t=in:st=0:d=0.35,fade=t=out:st=$(echo "$1 - 0.35" | bc):d=0.35"; }

seq_seg() { # scene dir, seconds
  ffmpeg -loglevel error -y -framerate 30 -i "$V/$1/%04d.png" -vf "$(fade "$2")" "${enc[@]}" "$V/seg/$1.mp4"
}
still_seg() { # image, seconds, name  (slow 4% zoom, fitted to 1920x1080)
  ffmpeg -loglevel error -y -loop 1 -t "$2" -i "$1" -vf \
    "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x1a1417,\
zoompan=z='1+0.04*on/($2*30)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps=30,$(fade "$2")" \
    "${enc[@]}" "$V/seg/$3.mp4"
}

seq_seg s1 4.5
seq_seg s2 3.5
seq_seg s3 4.5

# Real footage: speed up to TARGET seconds, fit into 1600x900, overlay on the backdrop.
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$REC")
SPEED=$(echo "scale=4; $DUR / $TARGET" | bc)
ffmpeg -loglevel error -y -loop 1 -i "$V/frame/0000.png" -i "$REC" -filter_complex \
  "[1:v]setpts=PTS/$SPEED,fps=30,scale=1600:900:force_original_aspect_ratio=decrease,pad=1600:900:(ow-iw)/2:(oh-ih)/2:color=0x111111[f];\
[0:v][f]overlay=160:160:shortest=1,$(fade "$TARGET")" -an -t "$TARGET" "${enc[@]}" "$V/seg/s4.mp4"

still_seg docs/promo/how-it-works.png 4 diagram
seq_seg s5 4.5
still_seg docs/promo/social-preview.png 4 end

printf "file 'seg/%s.mp4'\n" s1 s2 s3 s4 diagram s5 end > "$V/list.txt"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$V/list.txt" -c copy "$V/promo-silent.mp4"
bash tools/make-audio.sh   # voice-over, SFX, music -> $OUT/autoapprove-promo.mp4

# README GIF: the real footage only, 900 px wide, 12 fps, 2-pass palette.
ffmpeg -loglevel error -y -i "$V/seg/s4.mp4" -vf "fps=12,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" "$OUT/demo.gif"

ls -lh "$OUT"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/autoapprove-promo.mp4"
