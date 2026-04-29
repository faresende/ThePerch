#!/bin/bash
# install-inbody-watcher.sh
#
# Renders the launchd plist template with this machine's paths and
# installs it as a user agent. Idempotent: safe to re-run.
#
# Defaults can be overridden via env:
#   WATCH_DIR  — where to look for InBody-*.csv exports
#                (default: ~/Documents/InBody)
#   LOG_DIR    — where the watcher's stdout/err logs land
#                (default: ~/.openclaw/logs)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/ops/launchd/com.theperch.inbody-watcher.plist.template"
TARGET="$HOME/Library/LaunchAgents/com.theperch.inbody-watcher.plist"

WATCH_DIR="${WATCH_DIR:-$HOME/Documents/InBody}"
LOG_DIR="${LOG_DIR:-$HOME/.openclaw/logs}"

mkdir -p "$WATCH_DIR" "$LOG_DIR" "$(dirname "$TARGET")"

# Substitute placeholders. sed delimiter is `|` so paths don't escape.
sed \
  -e "s|__REPO_ROOT__|$REPO_ROOT|g" \
  -e "s|__WATCH_DIR__|$WATCH_DIR|g" \
  -e "s|__LOG_DIR__|$LOG_DIR|g" \
  "$TEMPLATE" > "$TARGET"

# Reload (idempotent — unload swallows errors if not loaded).
launchctl unload "$TARGET" 2>/dev/null || true
launchctl load "$TARGET"

echo "Installed: $TARGET"
echo "Watching:  $WATCH_DIR"
echo "Logs:      $LOG_DIR/inbody-watcher.{out,err}.log"
echo
echo "Drop an InBody-*.csv into $WATCH_DIR. Within 60s the watcher will"
echo "ingest it (deletes the file on success) and regenerate the BioChecha"
echo "post-wake insight on iOS + Telegram."
