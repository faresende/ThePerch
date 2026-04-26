#!/bin/bash
# Run by ~/Library/LaunchAgents/com.theperch.poll-shipments.plist
# every 30 minutes. Polls 17track for all undelivered shipments and
# updates each one's status; if 17track says delivered, the order
# auto-moves to the Delivered section (no manual long-press needed).

set -e
set -a; source ~/.openclaw/secrets/perch.env; set +a

LOG_DIR=~/.openclaw/logs
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/poll-shipments.log"
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
echo "[$(ts)] poll-shipments start" >> "$LOG_FILE"

# /opt/homebrew is M-series Homebrew. /usr/local for Intel.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

OUT=$(node ~/.openclaw/skills/dashboard-sync/cli.js poll-shipments \
        --user_id "$PERCH_USER_ID" 2>&1) || EC=$?
echo "[$(ts)] $OUT" >> "$LOG_FILE"
exit ${EC:-0}
