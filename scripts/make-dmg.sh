#!/bin/bash
# Builds the app, then a compressed disk image with it and an Applications
# shortcut: dist/Double-Trouble-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP_NAME="Double Trouble"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "dist/$APP_NAME.app/Contents/Info.plist")"
DMG="dist/Double-Trouble-$VERSION.dmg"

echo "▸ Immagine disco $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "dist/$APP_NAME.app" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs APFS -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
