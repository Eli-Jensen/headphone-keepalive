#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.$(whoami).headphone-keepalive"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

# Remove the hpk control command if it points at this repo
for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  link="$d/hpk"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$SCRIPT_DIR/hpk" ]; then
    rm -f "$link"; echo "removed $link"
  fi
done

echo "✓ Uninstalled $LABEL. (Source and compiled binary left in place.)"
