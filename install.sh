#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Compiling keepalive…"
swiftc -O "$SCRIPT_DIR/keepalive.swift" -o "$SCRIPT_DIR/keepalive"

# Put the hpk control command on PATH.
chmod +x "$SCRIPT_DIR/hpk"
for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  if [ -d "$d" ] && [ -w "$d" ]; then
    ln -sf "$SCRIPT_DIR/hpk" "$d/hpk"
    echo "✓ Control command: $d/hpk  (try: hpk help)"
    break
  fi
done

# hpk owns the LaunchAgent: generate it from settings (config file or defaults) and start.
"$SCRIPT_DIR/hpk" apply >/dev/null
"$SCRIPT_DIR/hpk" on

echo "✓ Installed and running:"
"$SCRIPT_DIR/hpk" config