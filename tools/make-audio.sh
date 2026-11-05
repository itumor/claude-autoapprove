#!/bin/bash
# Add voice-over, sound effects and a music bed to the promo video.
#   tools/make-audio.sh            -> docs/media/autoapprove-promo.mp4 (with audio)
# Voice: ElevenLabs if .env is filled (bash tools/set-env.sh), else macOS `say` (VOICE=..., RATE=...).
# TTS=say forces the Mac voice. YES=1 skips the credit prompt. Lines + start times: tools/voiceover.txt.
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
starts=(); lines=()
while IFS='|' read -r start line; do
  [[ -z $start || $start == \#* ]] && continue
  starts+=("$start"); lines+=("$line")
done < "${VO:-tools/voiceover.txt}"   # VO=file: generate a subset (e.g. a one-line test)
n=${#lines[@]}

# ElevenLabs when .env has a key and a voice ID, else macOS `say`. Each line is cached by
# hash(voice, model, settings, text) in build/audio/cache, so a re-run only pays for changed lines.
env_get() { [[ -f .env ]] && grep -E "^$1=" .env | cut -d= -f2- || true; }
EL_KEY="${ELEVENLABS_API_KEY:-$(env_get ELEVENLABS_API_KEY)}"
EL_VOICE="${ELEVENLABS_VOICE_ID:-$(env_get ELEVENLABS_VOICE_ID)}"
EL_MODEL="${ELEVENLABS_MODEL:-eleven_v4}"   # highest quality; v4 takes only stability + similarity_boost
EL_SETTINGS='{"stability":0.5,"similarity_boost":0.75}'
TTS="${TTS:-$([[ -n $EL_KEY && -n $EL_VOICE ]] && echo elevenlabs || echo say)}"
mkdir -p "$A/cache"
vfile=()
for ((k=0; k<n; k++)); do
  h=$(printf '%s|%s|%s|%s' "$EL_VOICE" "$EL_MODEL" "$EL_SETTINGS" "${lines[$k]}" | shasum -a 256 | cut -c1-16)
  vfile+=("$A/cache/el-$h.mp3")
done
if [[ $TTS == elevenlabs ]]; then
  todo=0; chars=0
  for ((k=0; k<n; k++)); do [[ -s ${vfile[$k]} ]] || { todo=$((todo+1)); chars=$((chars+${#lines[$k]})); }; done
  echo "ElevenLabs ($EL_MODEL): $todo of $n lines to generate, $chars characters (~$chars credits). Cached lines are free."
  if (( todo > 0 )) && [[ ${YES:-} != 1 ]]; then
    read -rp "Spend ~$chars credits? [y/N] " ok; [[ $ok == [yY] ]] || { echo "stopped, nothing spent"; exit 1; }
  fi
  for ((k=0; k<n; k++)); do
    [[ -s ${vfile[$k]} ]] && continue
    body=$(jq -n --arg t "${lines[$k]}" --arg m "$EL_MODEL" --argjson s "$EL_SETTINGS" \
      --arg p "${lines[$((k-1))]:-}" --arg x "${lines[$((k+1))]:-}" \
      '{text:$t, model_id:$m, voice_settings:$s} + (if $p != "" then {previous_text:$p} else {} end) + (if $x != "" then {next_text:$x} else {} end)')
    [[ $k == 0 ]] && body=$(jq 'del(.previous_text)' <<< "$body")
    tmp="${vfile[$k]}.part"
    # Key goes in via a header file descriptor, not argv (keeps it out of `ps`).
    code=$(curl -sS -o "$tmp" -D "$tmp.h" -w '%{http_code}' -X POST \
      "https://api.elevenlabs.io/v1/text-to-speech/$EL_VOICE?output_format=mp3_44100_128" \
      -H @<(printf 'xi-api-key: %s\n' "$EL_KEY") -H 'Content-Type: application/json' -d "$body")
    if [[ $code != 200 ]]; then echo "ElevenLabs error $code on line $((k+1)):" >&2; cat "$tmp" >&2; echo >&2; rm -f "$tmp" "$tmp.h"; exit 1; fi
    used=$(grep -i '^x-character-count:' "$tmp.h" | tr -dc 0-9); rm -f "$tmp.h"
    mv "$tmp" "${vfile[$k]}"; echo "  line $((k+1)) ok (${used:-?} characters billed)"
  done
else
  for ((k=0; k<n; k++)); do vfile[$k]="$A/v$k.aiff"; say -v "$VOICE" -r "$RATE" -o "${vfile[$k]}" "$(sed -E 's/\[[a-z ,-]+\] ?//g' <<< "${lines[$k]}")"; done
fi
[[ -n ${VO:-} ]] && { echo "test only, video untouched:"; printf '  %s\n' "${vfile[@]}"; exit 0; }

# A line longer than its slot is sped up (max 1.2x) instead of regenerated: no extra credits.
tempo=()
for ((k=0; k<n; k++)); do
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${vfile[$k]}")
  next=${starts[$((k+1))]:-$DUR}; slot=$(echo "$next - ${starts[$k]} - 0.1" | bc)
  tp=$(echo "if ($d > $slot) $d / $slot else 1" | bc -l)
  if (( $(echo "$tp > 1.2" | bc) )); then
    echo "warning: line $((k+1)) is ${d}s for a ${slot}s slot; even at 1.2x it overlaps. Move start times in tools/voiceover.txt." >&2; tp=1.2
  fi
  (( $(echo "$tp > 1" | bc) )) && echo "line $((k+1)): ${d}s in a ${slot}s slot -> tempo $(printf %.3f "$tp")"
  tempo+=("$tp")
done
vin=(); vf=""
for ((i=0; i<n; i++)); do
  vin+=(-i "${vfile[$i]}"); vf+="[$i:a]aresample=48000,atempo=${tempo[$i]},adelay=$(echo "${starts[$i]}*1000/1" | bc):all=1[v$i];"
done
i=$n
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
