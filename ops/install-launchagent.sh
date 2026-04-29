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

# Validate paths against XML/control chars before interpolating into
# the plist. Both $HOME and $REPO_ROOT come from the user's environment;
# without this an attacker who controlled either could break out of
# `<string>...</string>` blocks.
_validate_path() {
  local name="$1" val="$2"
  if [[ "$val" =~ [[:cntrl:]] ]] || [[ "$val" == *'<'* ]] || [[ "$val" == *'>'* ]] || [[ "$val" == *'&'* ]] || [[ "$val" == *'"'* ]]; then
    echo "❌ $name contains XML/control chars: $val" >&2
    exit 2
  fi
  if [[ "${val:0:1}" != "/" ]]; then
    echo "❌ $name must be an absolute path: $val" >&2
    exit 2
  fi
}
_validate_path "HOME" "$HOME"
_validate_path "REPO_ROOT" "$REPO_ROOT"

# Substitute __HOME__ → $HOME and __REPO_ROOT__ → $REPO_ROOT, then
# write to ~/Library/LaunchAgents.
sed -e "s|__HOME__|$HOME|g" -e "s|__REPO_ROOT__|$REPO_ROOT|g" "$TEMPLATE" > "$TARGET"
chmod 644 "$TARGET"

# Make sure the program is executable. Failing to set +x is the most
# common reason a fresh install silently doesn't fire.
if [[ ! -x "$REPO_ROOT/ops/poll-shipments.sh" ]]; then
  chmod +x "$REPO_ROOT/ops/poll-shipments.sh"
fi

launchctl load "$TARGET"

echo "✓ Installed $LABEL"
echo "  plist:  $TARGET"
echo "  logs:   $HOME/.openclaw/logs/poll-shipments.log"
echo ""
echo "It will run every 30 minutes (and once on load). To stop:"
echo "  launchctl unload $TARGET"
