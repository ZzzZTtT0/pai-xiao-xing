#!/bin/bash
set -euo pipefail
PET_LABEL="local.paixiaoxing.codex-launch"
PET_AGENT="$HOME/Library/LaunchAgents/$PET_LABEL.plist"
/bin/launchctl bootout "gui/$(id -u)/$PET_LABEL" >/dev/null 2>&1 || true
if [ -f "$PET_AGENT" ]; then /bin/rm "$PET_AGENT"; fi
printf '已关闭 Codex 自动启动联动。派小星仍可手动运行。\n'
