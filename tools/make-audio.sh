#!/bin/bash
# Add voice-over, sound effects and a music bed to the promo video.
#   tools/make-audio.sh            -> docs/media/autoapprove-promo.mp4 (with audio)
# Voice: macOS `say` (VOICE=..., RATE=...). Lines + start times: tools/voiceover.txt.
# Needs: ffmpeg. Run tools/make-video.sh first (it writes the silent build/video/promo-silent.mp4).
set -euo pipefail
cd "$(dirname "$0")/.."
VOICE="${VOICE:-Samantha}"; RATE="${RATE:-175}"
A=build/audio; SILENT=build/video/promo-silent.mp4; OUT=docs/media/autoapprove-promo.mp4
mkdir -p "$A"
[[ -f $SILENT ]] || { echo "missing $SILENT: run tools/make-video.sh first" >&2; exit 1; }
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SILENT")

gen() { ffmpeg -loglevel error -y -f lavfi -i "$2" -ar 48000 -ac 1 "$A/$1.wav"; }
# ponytail: synthesized SFX (no samples to license); swap in real samples if they sound too plain.
gen pop     "aevalsrc='0.45*sin(2*PI*(500+500*exp(-t*35))*t)*exp(-t*22)':d=0.3"
gen click   "aevalsrc='0.5*sin(2*PI*2400*t)*exp(-t*150)+0.3*sin(2*PI*900*t)*exp(-t*90)':d=0.08"
gen chime   "aevalsrc='0.25*(sin(2*PI*1318.5*t)+0.7*sin(2*PI*1975.5*t)+0.4*sin(2*PI*2637*t))*exp(-t*3.5)':d=1.6"
gen ding    "aevalsrc='0.3*(sin(2*PI*1046.5*t)+0.5*sin(2*PI*2093*t))*exp(-t*6)':d=0.8"
gen tick    "aevalsrc='0.22*sin(2*PI*1568*t)*exp(-t*40)':d=0.15"
gen beep    "aevalsrc='0.22*sin(2*PI*1000*t)*lt(t,0.07)':d=0.1"
gen flat    "aevalsrc='0.18*sin(2*PI*1000*t)*min(1,(1.4-t)/0.6)':d=1.4"
ffmpeg -loglevel error -y -f lavfi -i "anoisesrc=d=0.9:c=pink:a=0.5" \
  -af "volume='sin(PI*t/0.9)^2':eval=frame,bandpass=f=1800:w=2500" -ar 48000 -ac 1 "$A/whoosh.wav"
# Music bed: power-chord pad over C-A-F-G (4 s each) + soft pulse at 120 bpm.
ffmpeg -loglevel error -y -f lavfi -i "aevalsrc='\
st(0,if(lt(mod(t,16),4),130.81,if(lt(mod(t,16),8),110,if(lt(mod(t,16),12),87.31,98))));\
0.10*(sin(2*PI*ld(0)*t)+0.6*sin(2*PI*ld(0)*1.5*t)+0.4*sin(2*PI*ld(0)*2*t)+0.25*sin(2*PI*ld(0)*3*t))*min(1,min(mod(t,4),4-mod(t,4))*5)\
+0.22*sin(2*PI*52*t)*exp(-mod(t,0.5)*14)':d=$DUR" \
  -af "lowpass=f=1400,afade=t=in:d=1.5,afade=t=out:st=$(echo "$DUR - 2" | bc):d=2" -ar 48000 -ac 1 "$A/music.wav"

# Voice lines, each placed at its start time.
vin=(); vf=""; i=0
while IFS='|' read -r start line; do
  [[ -z $start || $start == \#* ]] && continue
  say -v "$VOICE" -r "$RATE" -o "$A/v$i.aiff" "$line"
  vin+=(-i "$A/v$i.aiff"); vf+="[$i:a]aresample=48000,adelay=$(echo "$start*1000/1" | bc):all=1[v$i];"; i=$((i+1))
done < tools/voiceover.txt
vmix=""; for ((k=0; k<i; k++)); do vmix+="[v$k]"; done
ffmpeg -loglevel error -y "${vin[@]}" -filter_complex "${vf}${vmix}amix=inputs=$i:normalize=0,apad,atrim=0:$DUR[o]" -map "[o]" -ar 48000 "$A/voice.wav"

# SFX cues (seconds): see app/make-video.swift scene timings and the footage.
cues="pop:0.5 pop:0.95 pop:1.4 pop:1.85 pop:2.3 whoosh:4.3 chime:4.9 click:9.0 click:10.4 ding:10.5 \
whoosh:12.3 ding:15.5 tick:16.4 tick:17.5 tick:18.3 tick:19.4 ding:21.1 whoosh:28.3 \
beep:32.1 beep:32.35 beep:32.6 flat:32.7 whoosh:36.1 chime:36.6"
sin=(); sf=""; j=0
for c in $cues; do
  sin+=(-f wav -i "$A/${c%%:*}.wav"); sf+="[$j:a]adelay=$(echo "${c##*:}*1000/1" | bc):all=1[s$j];"; j=$((j+1))
done
smix=""; for ((k=0; k<j; k++)); do smix+="[s$k]"; done
ffmpeg -loglevel error -y "${sin[@]}" -filter_complex "${sf}${smix}amix=inputs=$j:normalize=0,apad,atrim=0:$DUR[o]" -map "[o]" "$A/sfx.wav"

# Mix: music ducked under the voice, then loudness-normalized to -16 LUFS (web/social).
ffmpeg -loglevel error -y -i "$A/voice.wav" -i "$A/music.wav" -i "$A/sfx.wav" -filter_complex \
  "[0:a]asplit[v][key];[1:a]volume=0.55[m];[m][key]sidechaincompress=threshold=0.03:ratio=8:attack=20:release=400[md];\
[v][md][2:a]amix=inputs=3:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11[o]" -map "[o]" -ar 48000 "$A/mix.wav"
ffmpeg -loglevel error -y -i "$SILENT" -i "$A/mix.wav" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 160k -shortest -movflags +faststart "$OUT"
ls -lh "$OUT"
