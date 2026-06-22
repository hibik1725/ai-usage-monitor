#!/bin/bash
# Build QuotaBar.app + embedded WidgetKit extension (no Xcode required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="QuotaBar"
WIDGET_NAME="QuotaBarWidget"
BUNDLE="dist/${APP_NAME}.app"
APPEX="dist/${WIDGET_NAME}.appex"
GROUP_ID="group.com.hivvv.quotabar"
GROUP_DIR="${HOME}/Library/Group Containers/${GROUP_ID}"

echo "▸ Ensuring App Group container…"
mkdir -p "$GROUP_DIR"

BUILD_DIR=".build/arm64-apple-macosx/release"

echo "▸ Building release binaries…"
swift build -c release --product "$APP_NAME"
swift build -c release --target "$WIDGET_NAME"

echo "▸ Linking widget extension (MH_BUNDLE)…"
WIDGET_BIN="$BUILD_DIR/${WIDGET_NAME}-bundle"
swiftc -emit-executable \
    "$BUILD_DIR/QuotaBarWidget.build/"*.o \
    "$BUILD_DIR/QuotaBarCore.build/"*.o \
    -o "$WIDGET_BIN" \
    -O \
    -Xlinker -bundle \
    -Xlinker -rpath -Xlinker @executable_path/../../../../Frameworks \
    -Xlinker -rpath -Xlinker @executable_path/../../../../../Frameworks \
    -framework WidgetKit \
    -framework SwiftUI \
    -framework Foundation \
    -framework AppKit \
    -framework SwiftUI

echo "▸ Assembling widget extension…"
rm -rf "$APPEX"
mkdir -p "$APPEX/Contents/MacOS"
mkdir -p "$APPEX/Contents/Resources"
cp "$WIDGET_BIN" "$APPEX/Contents/MacOS/${WIDGET_NAME}"
cp "Resources/WidgetInfo.plist" "$APPEX/Contents/Info.plist"

echo "▸ Assembling ${BUNDLE}…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/PlugIns"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BUILD_DIR/${APP_NAME}" "$BUNDLE/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp Resources/icons/*.svg "$BUNDLE/Contents/Resources/"
cp -R "$APPEX" "$BUNDLE/Contents/PlugIns/"

echo "▸ Code signing with entitlements…"
codesign --force --sign - --entitlements "Resources/QuotaBar.entitlements" "$BUNDLE/Contents/MacOS/${APP_NAME}"
codesign --force --sign - --entitlements "Resources/QuotaBarWidget.entitlements" "$APPEX"
codesign --force --sign - --deep "$BUNDLE"

echo "▸ Registering widget extension…"
pluginkit -a "$BUNDLE/Contents/PlugIns/${WIDGET_NAME}.appex" 2>/dev/null || true

echo "✓ Built $BUNDLE"
echo "  Widget:  $BUNDLE/Contents/PlugIns/${WIDGET_NAME}.appex"
echo "  Shared:  $GROUP_DIR/usage-snapshot.json"
echo "  Run:     open \"$ROOT/$BUNDLE\""
echo "  Install: cp -R \"$ROOT/$BUNDLE\" /Applications/"