#!/bin/bash
# Claude Usage Widget — installer. Safe: backs up your settings, never overwrites an existing statusLine
# (it is chained instead), and everything can be removed with ./uninstall.sh.
set -euo pipefail
cd "$(dirname "$0")"

[ "$(uname)" = "Darwin" ] || { echo "macOS only."; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc not found. Install the Xcode Command Line Tools: xcode-select --install"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found."; exit 1; }

DATA="$HOME/.claude-usage-widget"
SETTINGS="$HOME/.claude/settings.json"
AGENT="$HOME/Library/LaunchAgents/com.claudeusagewidget.plist"
BIN="$DATA/ClaudeUsageWidget"
COLLECTOR="$DATA/usage-statusline.py"

mkdir -p "$DATA" "$HOME/.claude" "$HOME/Library/LaunchAgents"

echo "→ Building the widget…"
swiftc -O src/main.swift -o "$BIN"
cp collector/usage-statusline.py "$COLLECTOR"; chmod +x "$COLLECTOR"

echo "→ Updating Claude Code settings (backup first)…"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS" 2>/dev/null \
  || { echo "Your $SETTINGS is not valid JSON. Fix it first; nothing was changed."; exit 1; }
cp "$SETTINGS" "$SETTINGS.bak-usagewidget-$(date +%Y%m%d%H%M%S)"
python3 - "$SETTINGS" "$COLLECTOR" "$DATA" <<'PY'
import json, sys
path, collector, data = sys.argv[1:4]
s = json.load(open(path))
cur = (s.get("statusLine") or {}).get("command")
if cur and cur != collector:
    open(data + "/previous-statusline.txt", "w").write(cur)   # chained by the collector
s["statusLine"] = {"type": "command", "command": collector}
hook = {"type": "command", "command": "pkill -USR1 ClaudeUsageWidget || launchctl kickstart gui/$(id -u)/com.claudeusagewidget; true"}
for ev in ("SessionStart", "SessionEnd"):
    groups = s.setdefault("hooks", {}).setdefault(ev, [])
    if not any(h.get("command") == hook["command"] for g in groups for h in g.get("hooks", [])):
        groups.append({"hooks": [hook]})
json.dump(s, open(path, "w"), indent=2, ensure_ascii=False)
PY

echo "→ Start at login…"
cat > "$AGENT" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.claudeusagewidget</string>
<key>ProgramArguments</key><array><string>$BIN</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
PL
if [ -z "${NO_LAUNCH:-}" ]; then
  launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
fi
echo "✓ Done. Open a Claude Code session to feed the widget. Toggle it with ⌃⌥⌘U."
