#!/bin/bash
# Keep the Parakeet speech server always on: starts at login, restarts if it stops.
# One server (port 8774) then serves Dictate and anything else on this Mac, such as Hermes.
#   bash scripts/parakeet_agent.sh install     start now and at every login
#   bash scripts/parakeet_agent.sh uninstall   stop and remove
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL=com.dictate.parakeet
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
install)
  [ -x "$ROOT/.venv/bin/python" ] || { echo "Run scripts/setup.sh first."; exit 1; }
  "$ROOT/.venv/bin/python" "$ROOT/server/parakeet_srv.py" stop >/dev/null 2>&1 || true   # a hand-started server would hold the port
  sleep 2
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$ROOT/.venv/bin/python</string>
    <string>$ROOT/server/parakeet_srv.py</string>
    <string>serve</string><string>--idle</string><string>0</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>$ROOT/server/parakeet_srv.log</string>
  <key>StandardErrorPath</key><string>$ROOT/server/parakeet_srv.log</string>
</dict></plist>
PL
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$PLIST"
  echo "installed. Waiting for the model..."
  for _ in $(seq 1 60); do curl -sf -m 1 http://127.0.0.1:8774/health >/dev/null && { echo "speech server is up"; exit 0; }; sleep 1; done
  echo "not up yet; see $ROOT/server/parakeet_srv.log"; exit 1 ;;
uninstall)
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "removed" ;;
*) echo "usage: $0 install|uninstall"; exit 2 ;;
esac
