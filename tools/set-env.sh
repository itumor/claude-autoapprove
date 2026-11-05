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
echo "saved .env (key: ${key:+set, ${#key} chars}${key:-MISSING}, voice: ${voice:-MISSING})"
