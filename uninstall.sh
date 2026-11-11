#!/bin/bash
# Removes everything the installer added and restores your previous statusLine.
set -euo pipefail
DATA="$HOME/.claude-usage-widget"
SETTINGS="$HOME/.claude/settings.json"
AGENT="$HOME/Library/LaunchAgents/com.claudeusagewidget.plist"

launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
pkill -x ClaudeUsageWidget 2>/dev/null || true
rm -f "$AGENT"

if [ -f "$SETTINGS" ]; then
python3 - "$SETTINGS" "$DATA" <<'PY'
import json, sys, os
path, data = sys.argv[1:3]
s = json.load(open(path))
prev = data + "/previous-statusline.txt"
if "usage-statusline.py" in ((s.get("statusLine") or {}).get("command") or ""):
    if os.path.exists(prev) and open(prev).read().strip():
        s["statusLine"] = {"type": "command", "command": open(prev).read().strip()}
    else:
        s.pop("statusLine", None)
for ev in ("SessionStart", "SessionEnd"):
    groups = (s.get("hooks") or {}).get(ev, [])
    kept = []
    for g in groups:
        g["hooks"] = [h for h in g.get("hooks", []) if "ClaudeUsageWidget" not in h.get("command", "")]
        if g["hooks"]: kept.append(g)
    if ev in (s.get("hooks") or {}):
        if kept: s["hooks"][ev] = kept
        else: del s["hooks"][ev]
if "hooks" in s and not s["hooks"]: del s["hooks"]
json.dump(s, open(path, "w"), indent=2, ensure_ascii=False)
PY
fi
read -r -p "Delete the widget's data and history ($DATA)? [y/N] " a || a=n
if [ "$a" = "y" ] || [ "$a" = "Y" ]; then rm -rf "$DATA"; else rm -f "$DATA/ClaudeUsageWidget" "$DATA/usage-statusline.py"; fi
echo "✓ Uninstalled."
