#!/bin/bash
# Builds the app, then the release disk image: dist/Double-Trouble-<version>.dmg
# with a background, fixed icon positions and an Applications shortcut.
# Uses dmgbuild (needs Python 3.10+), installed on first run into .build/dmgbuild.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP_NAME="Double Trouble"
APP="dist/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="dist/Double-Trouble-$VERSION.dmg"

VENV=".build/dmgbuild"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
    # dmgbuild needs Python 3.10+; the one in the Command Line Tools is older.
    PY="${PYTHON:-python3}"
    if ! "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
        echo "Serve Python 3.10 o più recente (brew install python), oppure PYTHON=/percorso/python3" >&2
        exit 1
    fi
    echo "▸ Installo dmgbuild"
    rm -rf "$VENV"
    "$PY" -m venv "$VENV"
    "$VENV/bin/pip" install --quiet "dmgbuild==1.6.7"
fi

echo "▸ Immagine disco $DMG"
rm -f "$DMG"
# --no-hidpi: a 2x background breaks the layout in macOS 26 Finder.
"$VENV/bin/dmgbuild" --no-hidpi -s scripts/dmg-settings.py \
    -D app="$APP" \
    -D background=Design/dmg-background.png \
    -D volume_icon=Design/AppIcon.icns \
    "$APP_NAME" "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
