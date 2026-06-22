#!/bin/bash
# Build AppIcon.icns from Resources/AppIcon/AppIcon-1024.png (macOS iconutil).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/Resources/AppIcon/AppIcon-1024.png"
ICONSET="${ROOT}/Resources/AppIcon/AppIcon.iconset"
ICNS="${ROOT}/Resources/AppIcon/AppIcon.icns"

[[ -f "$SRC" ]] || { echo "✗ Missing $SRC" >&2; exit 1; }
command -v iconutil >/dev/null 2>&1 || { echo "✗ iconutil not found (macOS only)" >&2; exit 1; }
command -v sips >/dev/null 2>&1 || { echo "✗ sips not found" >&2; exit 1; }

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

resize() {
    local px="$1"
    local out="$2"
    sips -z "$px" "$px" "$SRC" --out "$ICONSET/$out" >/dev/null
}

resize 16  icon_16x16.png
resize 32  icon_16x16@2x.png
resize 32  icon_32x32.png
resize 64  icon_32x32@2x.png
resize 128 icon_128x128.png
resize 256 icon_128x128@2x.png
resize 256 icon_256x256.png
resize 512 icon_256x256@2x.png
resize 512 icon_512x512.png
cp -f "$SRC" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "✓ Generated $ICNS"