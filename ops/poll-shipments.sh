#!/bin/bash
# Run by ~/Library/LaunchAgents/com.theperch.poll-shipments.plist
# every 30 minutes. Polls 17track for all undelivered shipments and
# updates each one's status; if 17track says delivered, the order
# auto-moves to the Delivered section (no manual long-press needed).
#
# Uses $HOME throughout so it works on any user's machine without
# editing.

set -e

# Source secrets. Canonical openclaw location first; fall back to a
# sibling .env in the repo root for one-off manual runs.
if [[ -f "$HOME/.openclaw/secrets/perch.env" ]]; then
  set -a; source "$HOME/.openclaw/secrets/perch.env"; set +a
elif [[ -f "$(dirname "$0")/../.env" ]]; then
  set -a; source "$(dirname "$0")/../.env"; set +a
else
  echo "error: no perch.env found at \$HOME/.openclaw/secrets/perch.env or repo root" >&2
  exit 2
fi

LOG_DIR="$HOME/.openclaw/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/poll-shipments.log"
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
echo "[$(ts)] poll-shipments start" >> "$LOG_FILE"

# /opt/homebrew is M-series Homebrew. /usr/local for Intel.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

OUT=$(node "$HOME/.openclaw/skills/dashboard-sync/cli.js" poll-shipments \
        --user_id "$PERCH_USER_ID" 2>&1) || EC=$?
echo "[$(ts)] $OUT" >> "$LOG_FILE"
exit ${EC:-0}
