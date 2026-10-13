#!/bin/zsh
# Publishes a GitHub release that the in-app updater (Updater.swift) can find.
#   1. Raise CFBundleShortVersionString in Info.plist, commit and push.
#   2. scripts/release.sh [notes.md]
# The Markdown notes, if given, are shown in the update window and on GitHub.
# One-time setup (notarytool profile, Sparkle signing key): README › Releasing.
set -euo pipefail
cd "${0:A:h}/.."
SCRATCH="$HOME/Library/Caches/Nayantara-build"
REPO="mrinaliniisin/nayantara_icloud_monitor"
PROFILE="${NAYANTARA_NOTARY_PROFILE:-nayantara}"
NOTES="${1:-}"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null; }
fail() { echo "$1" >&2; exit 1; }

[[ -z "$(git status --porcelain)" ]] || fail "Commit your changes first: the build number is the commit count."
[[ -n "$(git branch -r --contains HEAD)" ]] || fail "Push first: GitHub tags the release on this commit."
[[ -z "$NOTES" || -f "$NOTES" ]] || fail "No such notes file: $NOTES"
plist SUPublicEDKey Info.plist >/dev/null || fail "Info.plist has no SUPublicEDKey yet; see README › Releasing."
VERSION="$(plist CFBundleShortVersionString Info.plist)"
TAG="v$VERSION"
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && fail "$TAG is already released; raise CFBundleShortVersionString in Info.plist."

./build.sh --release
APP="$SCRATCH/dist/Nayantara.app"
OUT="$SCRATCH/releases/$TAG"   # one archive per folder, so the appcast lists just this version
ZIP="$OUT/Nayantara-$VERSION.zip"
rm -rf "$OUT"
mkdir -p "$OUT"

# Notarize, then staple the ticket to the app so Gatekeeper accepts it offline,
# and zip the stapled copy: that zip is what gets published.
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Notarizing (usually a few minutes)…"
RESULT="$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json)"
STATUS="$(plutil -extract status raw - <<< "$RESULT")"
if [[ "$STATUS" != "Accepted" ]]; then
    ID="$(plutil -extract id raw - <<< "$RESULT")"
    xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2 || true
    fail "Notarization: $STATUS"
fi
xcrun stapler staple "$APP"
spctl --assess --type execute -vv "$APP"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# Signs the zip with the EdDSA key in the Keychain and writes appcast.xml.
# Notes are embedded, so a check fetches nothing but appcast.xml.
[[ -n "$NOTES" ]] && cp "$NOTES" "$OUT/Nayantara-$VERSION.md"
"$SCRATCH/artifacts/sparkle/Sparkle/bin/generate_appcast" --embed-release-notes \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://github.com/$REPO" "$OUT"

# The app's feed is releases/latest/download/appcast.xml, so publishing is all
# it takes for the update to reach people who turned updates on.
NOTE_ARGS=(--generate-notes)
[[ -n "$NOTES" ]] && NOTE_ARGS=(--notes-file "$NOTES")
gh release create "$TAG" "$ZIP" "$OUT/appcast.xml" --repo "$REPO" \
    --target "$(git rev-parse HEAD)" --title "Nayantara $VERSION" "${NOTE_ARGS[@]}"
echo "Released $TAG"
