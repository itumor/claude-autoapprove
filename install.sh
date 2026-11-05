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

backup() { cp "$S" "$S.bak.$(date +%s)"; }

if [[ "${1:-}" == "--uninstall" ]]; then
  backup
  jq --arg c "$HOOK" '.hooks.PermissionRequest |= map(select(.hooks | all(.command != $c)))' "$S" > "$S.tmp"
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
  jq --arg c "$HOOK" '.hooks.PermissionRequest += [{"matcher":"","hooks":[{"type":"command","command":$c}]}]' "$S" > "$S.tmp"
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
