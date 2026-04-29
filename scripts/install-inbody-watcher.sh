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

# Resolve repo root from this script's own location (works through symlinks).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPO_ROOT/ops/launchd/com.theperch.inbody-watcher.plist.template"
TARGET="$HOME/Library/LaunchAgents/com.theperch.inbody-watcher.plist"

WATCH_DIR="${WATCH_DIR:-$HOME/Documents/InBody}"
LOG_DIR="${LOG_DIR:-$HOME/.openclaw/logs}"

# ─── Validate env-supplied paths to prevent plist injection ────────────
# Both values are interpolated into <string>...</string> via sed below.
# Reject anything that:
#   - contains XML metacharacters (could break out of the plist string)
#   - contains a newline (sed pattern would match across lines)
#   - is not absolute (relative paths produce surprising launchd state)
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
_validate_path "REPO_ROOT" "$REPO_ROOT"
_validate_path "WATCH_DIR" "$WATCH_DIR"
_validate_path "LOG_DIR"   "$LOG_DIR"

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
