#!/bin/bash
# Build AutoApprove.app and copy to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/AutoApprove.app
mkdir -p "$APP/Contents/MacOS"
cp app/Info.plist "$APP/Contents/"
if [[ ! -f app/AppIcon.icns ]]; then
  swift app/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o app/AppIcon.icns
fi
mkdir -p "$APP/Contents/Resources"
cp app/AppIcon.icns "$APP/Contents/Resources/"
cp hook/patterns.json "$APP/Contents/Resources/"   # the risky list, shared with the hook
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/AutoApprove" app/AutoApprove.swift
# Sign with a stable identity so the Accessibility grant survives rebuilds.
# Ad-hoc (-) fallback: every rebuild needs Accessibility re-granted.
# Default: first valid code-signing identity in your keychain.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)}"
SIGN_ID="${SIGN_ID:--}"
codesign --force -s "$SIGN_ID" --identifier io.github.itumor.claude-autoapprove "$APP"
echo "signed with: $SIGN_ID"
"$APP/Contents/MacOS/AutoApprove" --selftest
mkdir -p ~/Applications
ditto "$APP" ~/Applications/AutoApprove.app
echo "built: ~/Applications/AutoApprove.app"
