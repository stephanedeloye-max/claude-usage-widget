#!/usr/bin/env python3
"""Claude Code statusLine command: records usage for the widget, then prints a status line.
If you had your own statusLine before installing, it is run and its output is kept."""
import sys, json, os, datetime, subprocess

data_dir = os.path.expanduser("~/.claude-usage-widget/")
raw = sys.stdin.read()

def passthrough():
    try:
        prev = open(data_dir + "previous-statusline.txt").read().strip()
        if prev:
            r = subprocess.run(prev, shell=True, input=raw, capture_output=True, text=True, timeout=5)
            return r.stdout.rstrip("\n") or "Claude"
    except Exception:
        pass
    return "Claude"

try:
    d = json.loads(raw)
    r = d.get("rate_limits") or {}
    now = datetime.datetime.now(datetime.timezone.utc)
    def iso(t):
        if isinstance(t, (int, float)):
            return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).isoformat().replace("+00:00", "Z")
        return str(t)
    w = []
    for k, l in (("five_hour", "Session de 5 h"), ("seven_day", "Semaine · tous modèles")):
        x = r.get(k)
        if x:
            w.append({"label": l, "percentUsed": x.get("used_percentage", 0), "resetsAt": iso(x.get("resets_at"))})
    if w:
        os.makedirs(data_dir, exist_ok=True)
        ts = now.isoformat().replace("+00:00", "Z")
        json.dump({"updated": ts, "windows": w}, open(data_dir + "usage-widget.json", "w"))
        cwd = (d.get("workspace") or {}).get("current_dir") or d.get("cwd") or ""
        rec = {"ts": ts, "session": d.get("session_id", ""), "project": os.path.basename(cwd.rstrip("/")) or "?",
               "five": (r.get("five_hour") or {}).get("used_percentage"),
               "seven": (r.get("seven_day") or {}).get("used_percentage"),
               "cost": (d.get("cost") or {}).get("total_cost_usd")}
        hp = data_dir + "usage-history.jsonl"
        # keep the history file small: trim to the last 20000 lines when it grows
        if os.path.exists(hp) and os.path.getsize(hp) > 4_000_000:
            lines = open(hp).read().splitlines()[-20000:]
            open(hp, "w").write("\n".join(lines) + "\n")
        with open(hp, "a") as f:
            f.write(json.dumps(rec) + "\n")
except Exception:
    pass
print(passthrough())
