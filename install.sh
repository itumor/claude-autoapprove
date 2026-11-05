#!/bin/bash
# Register the hook in ~/.claude/settings.json (idempotent, backs up first).
#   ./install.sh              add hook
#   ./install.sh --login      also start AutoApprove.app at login
#   ./install.sh --uninstall  remove hook + login item
set -euo pipefail
cd "$(dirname "$0")"
S="$HOME/.claude/settings.json"
HOOK="python3 $PWD/hook/autoapprove.py"
AGENT="$HOME/Library/LaunchAgents/io.github.itumor.claude-autoapprove.plist"

for t in jq python3; do command -v "$t" >/dev/null || { echo "missing $t: install it first (brew install $t)" >&2; exit 1; }; done
mkdir -p "$(dirname "$S")"
[[ -f "$S" ]] || echo '{}' > "$S"
[[ -L "$S" ]] && S="$(readlink -f "$S")"   # write through a symlinked settings.json, don't replace the link
# Remove only our hook entries (any repo path), keep other hooks in the same group, drop emptied groups.
DROP='def ours: (.command? // "") | tostring | test("hook/autoapprove\\.py\"?$");
  ((.hooks.PermissionRequest // []) | map(.hooks = ((.hooks // []) | map(select(ours | not)))) | map(select(.hooks | length > 0)))'
backup() { cp "$S" "$S.bak.$(date +%s)"; }

if [[ "${1:-}" == "--uninstall" ]]; then
  backup
  # Matches any repo path, so it also works after the repo moved.
  jq "$DROP as \$keep | .hooks.PermissionRequest = \$keep" "$S" > "$S.tmp"
  mv "$S.tmp" "$S"
  launchctl bootout "gui/$(id -u)" "$AGENT" || true
  [[ -f "$AGENT" ]] && mv "$AGENT" "$AGENT.removed"
  echo "hook + login item removed"
  exit 0
fi

if jq -e --arg c "$HOOK" '[.hooks.PermissionRequest[]?.hooks[]?.command] | index($c)' "$S" >/dev/null; then
  echo "hook already registered"
else
  backup
  # Drop an old entry from a previous repo path, then add this one.
  jq --arg c "$HOOK" "$DROP as \$keep | .hooks.PermissionRequest = \$keep + [{matcher: \"\", hooks: [{type: \"command\", command: \$c}]}]" "$S" > "$S.tmp"
  mv "$S.tmp" "$S"
  echo "hook registered in $S"
fi

if [[ "${1:-}" == "--login" ]]; then
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>io.github.itumor.claude-autoapprove</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$HOME/Applications/AutoApprove.app</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
  launchctl bootstrap "gui/$(id -u)" "$AGENT" || true
  echo "login item installed"
fi
