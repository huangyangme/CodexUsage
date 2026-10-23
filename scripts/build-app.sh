#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/codexusage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/CodexUsage.app"
mkdir -p "$APP/Contents/MacOS" "$ROOT/dist"
cp "$BIN_DIR/CodexUsage" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
# ZIP before copying into folders whose file provider may attach Finder metadata.
ditto -c -k --norsrc --keepParent "$APP" "$ROOT/dist/CodexUsage.zip"
ditto --norsrc "$APP" "$ROOT/dist/CodexUsage.app"
printf 'Built: %s/dist/CodexUsage.app\nArchive: %s/dist/CodexUsage.zip\n' "$ROOT" "$ROOT"
