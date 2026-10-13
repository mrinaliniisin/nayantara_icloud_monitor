#!/bin/zsh
# Builds Nayantara.app.
#   ./build.sh            development build, ad-hoc signed, installed in ~/Applications
#   ./build.sh --run      the same, then opens it
#   ./build.sh --release  Developer ID signed, hardened runtime, left in the build
#                         folder for scripts/release.sh to notarize (not installed)
# Build products live in ~/Library/Caches so they are never synced to iCloud
# (this source folder sits on the iCloud-synced Desktop).
set -euo pipefail
cd "${0:A:h}"
SCRATCH="$HOME/Library/Caches/Nayantara-build"

RUN=false RELEASE=false
for arg in "$@"; do
    case $arg in
        --run) RUN=true ;;
        --release) RELEASE=true ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

if $RELEASE; then
    APP="$SCRATCH/dist/Nayantara.app"
    # A unique part of the certificate's name is enough; override for another identity.
    IDENTITY="${NAYANTARA_SIGN_IDENTITY:-Developer ID Application}"
    SIGN=(--force --sign "$IDENTITY" --options runtime --timestamp)
else
    APP="$HOME/Applications/Nayantara.app"
    SIGN=(--force --sign -)
fi

swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"

$RELEASE || pkill -x Nayantara 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Nayantara" "$APP/Contents/MacOS/Nayantara"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate: swift scripts/make-icon.swift
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"   # ditto keeps its symlinks
cp "$SCRATCH/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE"   # MIT asks for its notice

# Sparkle compares CFBundleVersion, so every commit gets a higher one.
# CFBundleShortVersionString (what people see) is set by hand in Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"

# Inside out, never --deep: each nested piece needs its own signature first.
# Sparkle's own steps: https://sparkle-project.org/documentation/sandboxing/#code-signing
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if $RELEASE; then
    codesign "${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
    codesign "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
    codesign "${SIGN[@]}" "$SPARKLE/Autoupdate"
    codesign "${SIGN[@]}" "$SPARKLE/Updater.app"
    codesign "${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
fi
codesign "${SIGN[@]}" "$APP"

touch "$APP"   # nudge Finder/Dock to pick up a changed icon
echo "Built $APP ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"), build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"))"
$RUN && open "$APP"
exit 0
