#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.$(whoami).headphone-keepalive"
BIN="$SCRIPT_DIR/keepalive"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
IDLE_STOP="${1:-120}"

echo "Compiling keepalive…"
swiftc -O "$SCRIPT_DIR/keepalive.swift" -o "$BIN"

echo "Writing LaunchAgent → $PLIST"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
        <string>--quiet</string>
        <string>--idle-stop</string>
        <string>$IDLE_STOP</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>$SCRIPT_DIR/keepalive.log</string>
    <key>StandardErrorPath</key><string>$SCRIPT_DIR/keepalive.log</string>
</dict>
</plist>
EOF

echo "Loading…"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✓ Installed and running: $LABEL (pure silence, pause after ${IDLE_STOP}s idle)"
