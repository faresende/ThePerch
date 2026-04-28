#!/bin/bash
# Install the poll-shipments LaunchAgent.
#
# Substitutes __HOME__ in the .plist.template with the current user's
# $HOME, copies it into ~/Library/LaunchAgents/, and loads it.
#
# Idempotent: re-running unloads + reinstalls + reloads. Safe to
# run after pulling repo updates.
#
# Usage:
#   ./ops/install-launchagent.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/ops/com.theperch.poll-shipments.plist.template"
TARGET="$HOME/Library/LaunchAgents/com.theperch.poll-shipments.plist"
LABEL="com.theperch.poll-shipments"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "error: template not found at $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/.openclaw/logs"

# If already loaded, unload first so the next launchctl load picks up
# any path / interval changes from the template.
if launchctl list | grep -q "$LABEL"; then
  launchctl unload "$TARGET" 2>/dev/null || true
fi

# Substitute __HOME__ → actual $HOME and write to ~/Library/LaunchAgents.
sed "s|__HOME__|$HOME|g" "$TEMPLATE" > "$TARGET"
chmod 644 "$TARGET"

launchctl load "$TARGET"

echo "✓ Installed $LABEL"
echo "  plist:  $TARGET"
echo "  logs:   $HOME/.openclaw/logs/poll-shipments.log"
echo ""
echo "It will run every 30 minutes (and once on load). To stop:"
echo "  launchctl unload $TARGET"
