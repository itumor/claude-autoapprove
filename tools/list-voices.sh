#!/bin/bash
# List the ElevenLabs voices on your account (free: no credits used).
#   bash tools/list-voices.sh [filter]     e.g. bash tools/list-voices.sh male
# Reads the key from .env (bash tools/set-env.sh) or ELEVENLABS_API_KEY.
set -euo pipefail
cd "$(dirname "$0")/.."
key="${ELEVENLABS_API_KEY:-$( [[ -f .env ]] && grep -E '^ELEVENLABS_API_KEY=' .env | cut -d= -f2- || true)}"
[[ -n $key ]] || { echo "no key: run bash tools/set-env.sh first" >&2; exit 1; }
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
code=$(curl -sS -o "$tmp" -w '%{http_code}' "https://api.elevenlabs.io/v2/voices?page_size=100" \
  -H @<(printf 'xi-api-key: %s\n' "$key"))
[[ $code == 200 ]] || { echo "ElevenLabs error $code:" >&2; cat "$tmp" >&2; echo >&2; exit 1; }
jq -r '.voices[] | [.voice_id, .name, (.category // ""),
  ([.labels // {} | to_entries[] | .value] | join(", "))] | @tsv' "$tmp" |
  grep -i -- "${1:-}" | column -t -s $'\t'
