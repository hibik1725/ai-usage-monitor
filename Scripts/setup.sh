#!/bin/bash
# One-shot install: build, /Applications, login LaunchAgent, desktop panel on launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="QuotaBar"
BUNDLE_ID="com.hivvv.quotabar"
INSTALL_PATH="/Applications/${APP_NAME}.app"
PLIST_LABEL="com.hivvv.quotabar"
PLIST_DEST="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
GROUP_FILE="${HOME}/Library/Group Containers/group.com.hivvv.quotabar/usage-snapshot.json"
APPEX="${INSTALL_PATH}/Contents/PlugIns/QuotaBarWidget.appex"

info() { echo "▸ $*"; }
ok() { echo "✓ $*"; }
warn() { echo "⚠ $*"; }
die() { echo "✗ $1" >&2; exit 1; }

# --- Prerequisites ---

[[ "$(uname)" == "Darwin" ]] || die "macOS only"

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[[ "${MACOS_MAJOR}" -ge 14 ]] || die "macOS 14+ required (found $(sw_vers -productVersion))"

command -v swift >/dev/null 2>&1 || die "Swift not found. Install Xcode Command Line Tools: xcode-select --install"
command -v git >/dev/null 2>&1 || die "git not found"

info "Checking CLI credentials (at least one provider should be logged in)…"
HAVE_CODEX=false; HAVE_CLAUDE=false; HAVE_GROK=false
[[ -f "${HOME}/.codex/auth.json" ]] && HAVE_CODEX=true
security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 && HAVE_CLAUDE=true
[[ -f "${HOME}/.claude/.credentials.json" ]] && HAVE_CLAUDE=true
[[ -f "${HOME}/.grok/auth.json" ]] && HAVE_GROK=true
if ! $HAVE_CODEX && ! $HAVE_CLAUDE && ! $HAVE_GROK; then
    warn "No Codex / Claude / Grok credentials found. Install and log in to at least one CLI first."
    warn "  Codex:  https://github.com/openai/codex"
    warn "  Claude: https://docs.anthropic.com/en/docs/claude-code"
    warn "  Grok:   https://github.com/xai-org/grok-cli"
fi

# --- Build & install ---

info "Building ${APP_NAME}.app…"
./Scripts/build-app.sh

info "Stopping any running ${APP_NAME}…"
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.5

info "Installing to ${INSTALL_PATH}…"
rm -rf "${INSTALL_PATH}"
cp -R "dist/${APP_NAME}.app" "${INSTALL_PATH}"
ok "Installed ${INSTALL_PATH}"

# --- Login item (LaunchAgent) ---

info "Configuring login auto-start…"
mkdir -p "${HOME}/Library/LaunchAgents"
cp -f "${ROOT}/Scripts/com.hivvv.quotabar.plist" "${PLIST_DEST}"

GUI_UID="$(id -u)"
launchctl bootout "gui/${GUI_UID}" "${PLIST_DEST}" 2>/dev/null || launchctl unload "${PLIST_DEST}" 2>/dev/null || true
if launchctl bootstrap "gui/${GUI_UID}" "${PLIST_DEST}" 2>/dev/null; then
    ok "LaunchAgent bootstrapped (${PLIST_LABEL})"
else
    launchctl load "${PLIST_DEST}"
    ok "LaunchAgent loaded (${PLIST_LABEL})"
fi

# --- Preferences: show desktop panel on every launch ---

defaults write "${BUNDLE_ID}" showDesktopPanelOnLaunch -bool true
ok "Desktop panel will open on launch (showDesktopPanelOnLaunch=true)"

defaults write "${BUNDLE_ID}" sendTestNotificationOnLaunch -bool true
ok "Test notification will fire on first launch after setup"

# --- Widget extension registration ---

if [[ -d "${APPEX}" ]]; then
    pluginkit -a "${APPEX}" >/dev/null 2>&1 || true
    if pluginkit -m -v -i com.hivvv.quotabar.widget 2>/dev/null | grep -q 'com.hivvv.quotabar.widget'; then
        ok "WidgetKit extension registered (com.hivvv.quotabar.widget)"
    else
        warn "WidgetKit gallery registration skipped (ad-hoc signing). Floating desktop panel is enabled instead."
        warn "Optional: Desktop を右クリック → ウィジェットを編集 → QuotaBar (Medium) を追加"
    fi
fi

# --- Start app & verify ---

info "Starting ${APP_NAME}…"
open -a "${INSTALL_PATH}"

info "Requesting notification permission (approve the macOS dialog if shown)…"
sleep 2
if "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}" --test-notification 2>/dev/null; then
    ok "Test notification sent (osascript)"
else
    warn "Test notification failed — enable in System Settings → Notifications → QuotaBar"
fi
open "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=${BUNDLE_ID}" 2>/dev/null \
    || open "x-apple.systempreferences:com.apple.preference.notifications" 2>/dev/null || true

info "Waiting for first usage fetch…"
for _ in $(seq 1 30); do
    if [[ -f "${GROUP_FILE}" ]]; then
        break
    fi
    sleep 1
done

if [[ -f "${GROUP_FILE}" ]]; then
    ok "Shared snapshot written: ${GROUP_FILE}"
    python3 - <<'PY' "${GROUP_FILE}"
import json, sys
data = json.load(open(sys.argv[1]))
for p in data.get("providers", []):
    print(f"  {p['id']}: plan={p.get('plan', '?')}")
PY
else
    warn "Snapshot not found yet. Menu bar icon should appear; run: ${INSTALL_PATH}/Contents/MacOS/${APP_NAME} --probe"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " QuotaBar setup complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " • Menu bar: look for Cx / Cl / Gk percentages (top-right)"
echo " • Desktop:  floating Medium panel opens automatically"
echo " • Login:    auto-starts via LaunchAgent"
echo " • Alerts:   when usage drops below threshold (menu → 通知をテスト)"
echo ""
echo " Toggle desktop panel: click menu bar icon → デスクトップウィジェットを表示/隠す"
echo " Re-probe:             ${INSTALL_PATH}/Contents/MacOS/${APP_NAME} --probe"
echo " Uninstall:            ./Scripts/uninstall.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"