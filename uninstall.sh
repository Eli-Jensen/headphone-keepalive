#!/usr/bin/env bash
set -euo pipefail

LABEL="com.$(whoami).headphone-keepalive"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
echo "✓ Uninstalled $LABEL. (Source and compiled binary left in place.)"
