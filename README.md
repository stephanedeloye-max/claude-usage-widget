# Claude Usage Widget

A tiny floating macOS widget that shows your Claude Code usage: the 5-hour session and the weekly limit, what's left, when it resets, and a **forecast** of whether you'll hit the limit before the reset.

*Un petit widget macOS flottant qui affiche votre consommation Claude Code : session de 5 h, limite hebdomadaire, ce qui reste, la remise à zéro, et une **prévision** pour savoir si vous atteindrez la limite avant.*

## Features
- Transparent, draggable window, always on top (⌃⌥⌘U shows/hides it) + menu bar item
- Forecast: "Limit reached around 15:40, before the reset"
- Notifications at 70 %, 90 %, 100 %, and when the limit resets
- History: estimated cost per day and per project
- Right-click menu: refresh, compact view, history, transparency, size, hide, quit
- English and French (follows your system language)
- Starts at login

## Install
Requires macOS, python3 and the Xcode Command Line Tools (`xcode-select --install`).

```bash
bash install.sh
```

Then open a Claude Code session. The widget refreshes when a session opens or closes, and whenever Claude Code updates its status line.

## Uninstall
```bash
bash uninstall.sh
```

## How it works
- Claude Code passes your rate-limit usage to its *status line* command. A small script (`collector/usage-statusline.py`) saves it to `~/.claude-usage-widget/`.
- If you already had a status line, it is kept and still displayed (chained).
- Two hooks (SessionStart / SessionEnd) tell the widget to refresh.
- Your `~/.claude/settings.json` is backed up before any change (`settings.json.bak-usagewidget-…`).

## Privacy
Everything stays on your machine. No network access, no account, no tracking. The widget only reads files in `~/.claude-usage-widget/`.

## Known limits
- Depends on what Claude Code exposes in its status line; if that format changes, the widget may need an update. Usage data is only available after the first response of a session.
- Per-model limits (e.g. Fable) are not shown. Cost in the history is an estimate reported by Claude Code.
- Not signed/notarized: it is built from source on your Mac by `install.sh`, so macOS does not block it.
- Not affiliated with or endorsed by Anthropic.

## License
MIT
