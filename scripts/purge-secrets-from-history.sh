#!/usr/bin/env bash
# purge-secrets-from-history.sh
#
# Rewrites every commit in this repository to redact the literal secret
# strings that were confirmed leaked during the 2026-04-20 audit. Uses
# git-filter-repo's --replace-text mechanism.
#
# WHY THIS EXISTS
#   Deleting a file from HEAD does not remove its content from git history.
#   Every past commit still contains the secret. Anyone who has cloned the
#   repo (or forked it) can still find the secret with `git log -p`. This
#   script rewrites every commit in every branch so the literal strings
#   disappear entirely.
#
# DESTRUCTIVE WARNING
#   This rewrites every commit hash. After running:
#     1. You MUST force-push every branch (`git push --force-with-lease`).
#     2. Every collaborator MUST re-clone (old clones will diverge).
#     3. Every fork becomes a security risk; delete them or coordinate.
#     4. Local stashes and reflog entries are discarded by filter-repo.
#        Convert any stash you care about to a branch FIRST:
#          git stash branch rescued-work stash@{0}
#
# REQUIREMENTS
#   git-filter-repo (`brew install git-filter-repo`).
#
# USAGE
#   bash scripts/purge-secrets-from-history.sh           # interactive
#   bash scripts/purge-secrets-from-history.sh --yes     # skip prompt
#
# RECOMMENDED WORKFLOW (to keep the working repo safe until the very end)
#   1. Commit or convert every stash you want to keep.
#   2. Clone to a mirror:
#        git clone --mirror . /tmp/theperch-scrub.git
#   3. Run this script in that mirror:
#        cd /tmp/theperch-scrub.git
#        bash /path/to/scripts/purge-secrets-from-history.sh --mirror
#   4. Inspect the rewritten history.
#   5. Push from the mirror back to origin:
#        git push --mirror --force-with-lease
#   6. In the main working clone:
#        git fetch --all
#        git reset --hard origin/<branch>

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────

# Confirmed-leaked literals from /tmp/secrets-audit.md. If you discover new
# leaks, append to this list and re-run (filter-repo is idempotent on
# already-scrubbed strings).
#
# Format: literal==>replacement. The replacement is a short tag so that
# anyone reading the rewritten commits still sees WHY the content changed.

SCRUB_LITERALS=(
  # OpenAI project key (revoked by OpenAI on 2026-04-20)
  "REDACTED-openai-sk-proj==>REDACTED-openai-sk-proj"

  # Google API key: goplaces (rotated)
  "REDACTED-google-api-key==>REDACTED-google-api-key"

  # Google API key: nano-banana-pro (rotated)
  "REDACTED-google-api-key==>REDACTED-google-api-key"

  # OpenClaw gateway placeholder (never live, scrubbed for hygiene)
  "REDACTED-gateway-token==>REDACTED-stale-placeholder"

  # ElevenLabs API key for SAG voice skill (already rotated out of band)
  "REDACTED-elevenlabs-api-key==>REDACTED-elevenlabs-api-key"

  # Telegram bot token (rotated)
  "REDACTED-telegram-bot-token==>REDACTED-telegram-bot-token"

  # Legacy Supabase anon JWT signature tail. Matches the full JWT wherever
  # the line ends with this 43-char signature. Specific enough to avoid
  # false positives; broad enough to catch every embedding.
  "REDACTED-anon-jwt-sig==>REDACTED-anon-jwt-sig"
)

# ─── Pre-flight checks ────────────────────────────────────────────────────

SKIP_PROMPT=false
MIRROR_MODE=false
for arg in "$@"; do
  case "$arg" in
    --yes) SKIP_PROMPT=true ;;
    --mirror) MIRROR_MODE=true ;;
    -h|--help)
      sed -n '1,40p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "FATAL: git-filter-repo not found." >&2
  echo "Install with: brew install git-filter-repo" >&2
  exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FATAL: not inside a git repository." >&2
  exit 1
fi

if ! $MIRROR_MODE; then
  # Working-tree mode: warn loudly about state we will destroy.
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "FATAL: working tree is dirty. Commit or stash your changes first." >&2
    exit 1
  fi

  STASH_COUNT=$(git stash list | wc -l | tr -d ' ')
  if [[ "$STASH_COUNT" -gt 0 ]]; then
    echo "WARNING: you have $STASH_COUNT stash(es):" >&2
    git stash list >&2
    echo "" >&2
    echo "filter-repo will DELETE these. Rescue each one to a branch first:" >&2
    echo "    git stash branch rescued-\$(date +%s) stash@{N}" >&2
    echo "" >&2
    if ! $SKIP_PROMPT; then
      read -r -p "Proceed anyway and lose stashes? Type 'LOSE STASHES' to continue: " CONFIRM_STASH
      [[ "$CONFIRM_STASH" == "LOSE STASHES" ]] || { echo "Aborted."; exit 1; }
    fi
  fi
fi

# ─── Preview affected commits ─────────────────────────────────────────────

echo ""
echo "==================================================================="
echo " Commits that still contain at least one target literal:"
echo "==================================================================="
for entry in "${SCRUB_LITERALS[@]}"; do
  LITERAL="${entry%%==>*}"
  PREFIX="${LITERAL:0:20}"
  HITS=$(git log --all --oneline -S "$LITERAL" 2>/dev/null || true)
  if [[ -n "$HITS" ]]; then
    echo ""
    echo "Literal starting with: ${PREFIX}..."
    echo "$HITS"
  fi
done
echo ""
echo "==================================================================="
echo ""

# ─── Confirmation prompt ──────────────────────────────────────────────────

if ! $SKIP_PROMPT; then
  cat <<'EOF'
This will rewrite every commit in this repository. All commit hashes
will change. Every collaborator will need to re-clone. Forks must be
deleted or manually synced.

After this finishes, you still need to:
  1. Force-push every branch:     git push --force-with-lease --all
  2. Force-push every tag:        git push --force-with-lease --tags
  3. Delete forks on GitHub.
  4. Re-scan to confirm:          gitleaks detect --log-opts="--all"

EOF
  read -r -p 'Type "YES REWRITE HISTORY" to proceed: ' CONFIRM
  [[ "$CONFIRM" == "YES REWRITE HISTORY" ]] || { echo "Aborted."; exit 1; }
fi

# ─── Execute ──────────────────────────────────────────────────────────────

REPLACEMENTS_FILE="$(mktemp -t purge-secrets.XXXXXX)"
trap 'rm -f "$REPLACEMENTS_FILE"' EXIT

for entry in "${SCRUB_LITERALS[@]}"; do
  printf '%s\n' "$entry" >>"$REPLACEMENTS_FILE"
done

echo ""
echo "Running: git filter-repo --replace-text ..."
git filter-repo --replace-text "$REPLACEMENTS_FILE" --force
echo ""
echo "Done. Now:"
echo "  1. Inspect rewritten history:    git log --oneline -20"
echo "  2. Re-scan for leaks:            gitleaks detect --source . --log-opts=--all --redact"
echo "  3. Force-push to origin:         git push --force-with-lease --all && git push --force-with-lease --tags"
echo "  4. Notify collaborators to re-clone."
echo "  5. Delete forks on GitHub (Settings → Delete this repository) or coordinate with fork owners."
