#!/bin/bash
#
# inbody-watch-tick.sh — fires when ~/Documents/Claudio/ changes (via
# launchd WatchPaths). Ingests any InBody-*.csv into health_metrics
# and, if at least one CSV got consumed, regenerates the BioChecha
# post-wake insight (iOS card + Telegram briefing).
#
# Idempotent re-fire safety: when the ingest deletes the consumed
# CSV, that itself is a directory change that re-triggers launchd.
# We exit cleanly when there's nothing to ingest, and only fire
# the insight regenerate when the file count actually went down.

set -euo pipefail

WATCH_DIR="${INBODY_WATCH_DIR:-$HOME/Documents/Claudio}"
REPO_ROOT="$HOME/Developer/ThePerch"
SECRETS="$HOME/.openclaw/secrets/perch.env"

# ─── Pre-check: any CSVs to process? ──────────────────────────────────
if [ ! -d "$WATCH_DIR" ]; then
  exit 0
fi

# Glob safely even if no matches
shopt -s nullglob
csvs=("$WATCH_DIR"/InBody-*.csv "$WATCH_DIR"/InBody-*.CSV)
shopt -u nullglob
before=${#csvs[@]}
if [ "$before" -eq 0 ]; then
  exit 0
fi

# ─── Secrets ─────────────────────────────────────────────────────────
if [ ! -f "$SECRETS" ]; then
  echo "[inbody-watch] secrets file missing: $SECRETS" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "$SECRETS"
set +a

# ─── Ingest ──────────────────────────────────────────────────────────
/usr/bin/env python3 "$REPO_ROOT/agents/health-integrations/inbody_ingest.py"

# ─── Did we actually consume at least one CSV? ───────────────────────
shopt -s nullglob
after_csvs=("$WATCH_DIR"/InBody-*.csv "$WATCH_DIR"/InBody-*.CSV)
shopt -u nullglob
after=${#after_csvs[@]}

if [ "$after" -lt "$before" ]; then
  /usr/bin/env python3 "$REPO_ROOT/agents/health-integrations/biochecha_post_wake_insight.py"
else
  echo "[inbody-watch] ingest didn't consume any files (parse failures?); skipping post-wake regenerate" >&2
fi
