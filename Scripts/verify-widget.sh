#!/bin/bash
# Verify widget extension bundle + shared snapshot contract.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/QuotaBar.app"
APPEX="$APP/Contents/PlugIns/QuotaBarWidget.appex"
GROUP_FILE="${HOME}/Library/Group Containers/group.com.hivvv.quotabar/usage-snapshot.json"

fail() { echo "✗ $1" >&2; exit 1; }
ok() { echo "✓ $1"; }

[[ -d "$APPEX" ]] || fail "Widget extension missing at $APPEX"
file "$APPEX/Contents/MacOS/QuotaBarWidget" | rg -q "Mach-O 64-bit bundle" \
    || fail "Widget binary is not MH_BUNDLE"
ok "Widget binary is MH_BUNDLE"

[[ -f "$GROUP_FILE" ]] || fail "Shared snapshot missing: $GROUP_FILE"
python3 - <<'PY' "$GROUP_FILE" || exit 1
import json, sys
data = json.load(open(sys.argv[1]))
assert "providers" in data and len(data["providers"]) == 3
for p in data["providers"]:
    assert p["id"] in {"codex", "claude", "grok"}
print("providers:", ", ".join(f"{p['id']}({p.get('plan')})" for p in data["providers"]))
PY
ok "Shared snapshot has 3 providers"

pluginkit -a "$APPEX" >/dev/null 2>&1 || true
if pluginkit -m -v -i com.hivvv.quotabar.widget 2>/dev/null | rg -q 'com\.hivvv\.quotabar\.widget'; then
    ok "pluginkit registered com.hivvv.quotabar.widget"
else
    echo "⚠ pluginkit did not register extension (ad-hoc signing). Use menu「デスクトップウィジェットを表示」or Desktop → Edit Widgets."
fi

echo ""
echo "Manual add: Desktop を右クリック → ウィジェットを編集 → QuotaBar (Medium)"