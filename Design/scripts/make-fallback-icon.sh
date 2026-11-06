#!/bin/bash
# Builds Design/AppIcon.icns from Design/anteprima.svg for macOS before 26.
# Pre-26 grid: the artwork sits in the centered 824×824 area of the 1024 canvas,
# with a transparent margin. Needs rsvg-convert (brew install librsvg).
# The .icns is committed, so building the app does not need this script.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v rsvg-convert >/dev/null || { echo "rsvg-convert non trovato: brew install librsvg" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Wrap the 1024 artwork, scaled to 824 and centered.
sed -e '1d' -e '$d' anteprima.svg > "$TMP/body.svg"
{
    echo '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
    echo '<g transform="translate(100 100) scale(0.8046875)">'
    cat "$TMP/body.svg"
    echo '</g></svg>'
} > "$TMP/grid.svg"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$TMP/grid.svg" -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w $((size * 2)) -h $((size * 2)) "$TMP/grid.svg" -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o AppIcon.icns
echo "✅ Design/AppIcon.icns"
