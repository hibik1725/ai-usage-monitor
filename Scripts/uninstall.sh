#!/bin/bash
set -euo pipefail

APP_NAME="QuotaBar"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.hivvv.quotabar.plist"
GUI_UID="$(id -u)"

pkill -x "${APP_NAME}" 2>/dev/null || true
launchctl bootout "gui/${GUI_UID}" "${PLIST_DEST}" 2>/dev/null || launchctl unload "${PLIST_DEST}" 2>/dev/null || true
rm -f "${PLIST_DEST}"
rm -rf "/Applications/${APP_NAME}.app"
defaults delete com.hivvv.quotabar showDesktopPanelOnLaunch 2>/dev/null || true

echo "✓ QuotaBar uninstalled (LaunchAgent removed, /Applications/QuotaBar.app deleted)"