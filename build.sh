#!/bin/zsh
# Builds Nayantara.app into ~/Applications.
# Build products live in ~/Library/Caches so they are never synced to iCloud
# (this source folder sits on the iCloud-synced Desktop).
set -euo pipefail
cd "${0:A:h}"
SCRATCH="$HOME/Library/Caches/Nayantara-build"
APP="$HOME/Applications/Nayantara.app"

swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/Nayantara"

pkill -x Nayantara 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Nayantara"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate: swift scripts/make-icon.swift
codesign --force --sign - "$APP"
touch "$APP"   # nudge Finder/Dock to pick up a changed icon
echo "Built $APP"
[[ "${1:-}" == "--run" ]] && open "$APP"
