#!/bin/bash
# Builds dist/Double Trouble.app (Apple Silicon, ad-hoc signed)
# and a zip ready to share. Needs only the Xcode Command Line Tools.
#
#   ./scripts/build-app.sh          # build
#   ./scripts/build-app.sh --open   # build and launch
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Double Trouble"
VERSION="1.0"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "▸ Controlli del core"
swift run CoreChecks 2>/dev/null | tail -1 | tee /dev/stderr | grep -q " 0 falliti"

echo "▸ Traduzioni"
/usr/bin/python3 -I scripts/extract-strings.py --check Resources/en.lproj/Localizable.strings | tail -1

echo "▸ Compilo (Apple Silicon)"
swift build -c release --product ClaudeLauncher >/dev/null
BIN="$(swift build -c release --show-bin-path)/ClaudeLauncher"

echo "▸ Impacchetto $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Generated from Design/anteprima.svg by Design/scripts/make-fallback-icon.sh.
cp Design/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>local.double-trouble.app</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Fabrizio Mele. MIT License.</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>it</string></array>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key><string>Serve per portare in primo piano l'istanza di Claude giusta.</string>
</dict>
</plist>
EOF

echo "▸ Firma ad-hoc"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1
codesign --verify "$APP"

(cd "$DIST" && rm -f "$APP_NAME.zip" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")
echo "✅ $APP"
echo "   Da condividere: $DIST/$APP_NAME.zip"

if [ "${1:-}" = "--open" ]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    open "$APP"
fi
