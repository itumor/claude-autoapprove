#!/bin/bash
# Create or update .env (gitignored, mode 600) with the ElevenLabs settings for tools/make-audio.sh.
#   bash tools/set-env.sh
# The key is read hidden and never echoed. Leave an answer empty to keep the current value.
set -euo pipefail
cd "$(dirname "$0")/.."
git check-ignore -q .env || { echo "refusing: .env is not gitignored" >&2; exit 1; }
umask 077
touch .env && chmod 600 .env
cur() { grep -E "^$1=" .env | cut -d= -f2- || true; }
key=$(cur ELEVENLABS_API_KEY); voice=$(cur ELEVENLABS_VOICE_ID)

read -rsp "ElevenLabs API key (hidden, Enter = keep): " k; echo
[[ -n $k ]] && key=$k
read -rp "ElevenLabs voice ID (Enter = keep${voice:+ $voice}): " v
[[ -n $v ]] && voice=$v

{
  echo "# ElevenLabs settings for tools/make-audio.sh. Never commit (gitignored)."
  echo "ELEVENLABS_API_KEY=$key"
  echo "ELEVENLABS_VOICE_ID=$voice"
} > .env
echo "saved .env (key: ${key:+set, ${#key} chars, starts ${key:0:3}…}${key:-MISSING}, voice: ${voice:-MISSING})"
[[ $key =~ [[:space:]] ]] && echo "warning: the key contains spaces or line breaks; paste it again" >&2

# Free check (no credits): can this key read voices?
[[ -n $key ]] || exit 0
code=$(curl -sS -o /dev/null -w '%{http_code}' "https://api.elevenlabs.io/v2/voices?page_size=1" \
  -H @<(printf 'xi-api-key: %s\n' "$key"))
case $code in
  200) echo "key check: OK" ;;
  401) echo "key check: rejected (401). Wrong or partial key, or it lacks the Voices read permission." >&2 ;;
  *)   echo "key check: HTTP $code" >&2 ;;
esac
