#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# ThePerch — Deploy to TestFlight
# ─────────────────────────────────────────────────────────────

REPO_ROOT="$HOME/Documents/Apps/ThePerch"
PROJECT="$REPO_ROOT/ios/ThePerch/ThePerch.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
SCHEME="ThePerch"
ARCHIVE="/tmp/ThePerch.xcarchive"
EXPORT="/tmp/ThePerch-export"
EXPORT_OPTS="$REPO_ROOT/.xcodebuildmcp/ExportOptions.plist"
KEY="$HOME/.openclaw/secrets/AuthKey_87UBF99Q64.p8"
KEY_ID="87UBF99Q64"
ISSUER="69a6de81-7c5a-47e3-e053-5b8c7c11a4d1"
READINESS_GATE="$HOME/.openclaw/workspace/scripts/readiness-gate.sh"
DEFAULT_TELEGRAM_CHAT_ID="7126059841"
TELEGRAM_BOT_TOKEN="${THEPERCH_TELEGRAM_BOT_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}"
TELEGRAM_CHAT_ID="${THEPERCH_TELEGRAM_CHAT_ID:-${TELEGRAM_CHAT_ID:-$DEFAULT_TELEGRAM_CHAT_ID}}"

FORCE=false
SKIP_QA=false
SKIP_TESTS=false
LANE="alpha"
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --skip-qa) SKIP_QA=true ;;
    --skip-tests) SKIP_TESTS=true ;;
    --lane=alpha) LANE="alpha" ;;
    --lane=beta) LANE="beta" ;;
    --lane=*)
      echo "❌ Invalid lane '${arg#*=}'. Use --lane=alpha or --lane=beta."
      exit 1
      ;;
  esac
done

AUTH="-allowProvisioningUpdates -authenticationKeyPath $KEY -authenticationKeyID $KEY_ID -authenticationKeyIssuerID $ISSUER"

# ─────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────

cd "$REPO_ROOT"

echo "🔍 Pre-flight checks..."
echo "🛫 TestFlight lane: ${LANE}"

# 1. Branch check
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  if [ "$FORCE" = true ]; then
    echo "⚠️  WARNING: Not on main branch (on '$CURRENT_BRANCH'). Proceeding because --force was passed."
  else
    echo "❌ Must be on main branch to deploy (currently on '$CURRENT_BRANCH')."
    echo "   Use --force to override."
    exit 1
  fi
fi

# 2. Clean working directory (before we bump build number)
GIT_STATUS=$(git status --porcelain)
if [ -n "$GIT_STATUS" ]; then
  echo "❌ Working directory is not clean. Commit or stash changes before deploying."
  echo ""
  git status --short
  exit 1
fi

# ─────────────────────────────────────────────────────────────
# READINESS GATE (optional — warns but does not block)
# ─────────────────────────────────────────────────────────────

if [ -f "$READINESS_GATE" ]; then
  echo ""
  echo "🚦 Readiness Gate Check..."
  if bash "$READINESS_GATE" "$REPO_ROOT"; then
    echo "✅ Readiness gate: CLEARED"
  else
    echo "⚠️  Readiness gate: NOT CLEARED — proceeding anyway (gate is advisory)"
  fi
else
  echo "ℹ️  Readiness gate script not found at $READINESS_GATE — skipping check"
fi

# ─────────────────────────────────────────────────────────────
# TESTS (optional — run unit tests before deploy)
# ─────────────────────────────────────────────────────────────

TEST_RUNNER="$HOME/.openclaw/workspace/scripts/run-tests.sh"
if [ "$SKIP_TESTS" = false ] && [ -f "$TEST_RUNNER" ]; then
  echo ""
  echo "🧪 Running tests..."
  if bash "$TEST_RUNNER"; then
    echo "✅ Tests passed"
  else
    echo "❌ Tests failed. Aborting deploy."
    echo "   Use --skip-tests to bypass."
    exit 1
  fi
elif [ "$SKIP_TESTS" = true ]; then
  echo "⏭️  Skipping tests (--skip-tests)"
fi

# ─────────────────────────────────────────────────────────────
# QA PRE-DEPLOY (optional — build + launch in simulator)
# ─────────────────────────────────────────────────────────────

QA_SCRIPT="$HOME/.openclaw/workspace/scripts/qa-predeploy.sh"
if [ "$SKIP_QA" = false ] && [ -f "$QA_SCRIPT" ]; then
  echo ""
  echo "🔍 Running QA pre-deploy check..."
  if bash "$QA_SCRIPT"; then
    echo "✅ QA check passed"
  else
    echo "❌ QA check failed. Aborting deploy."
    echo "   Use --skip-qa to bypass."
    exit 1
  fi
elif [ "$SKIP_QA" = true ]; then
  echo "⏭️  Skipping QA check (--skip-qa)"
fi

# ─────────────────────────────────────────────────────────────
# BUILD NUMBER BUMP
# ─────────────────────────────────────────────────────────────

echo ""
echo "🔢 Bumping build number..."

CURRENT_BUILD=$(grep -m 1 "CURRENT_PROJECT_VERSION" "$PBXPROJ" | sed 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\).*/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "   Current build: $CURRENT_BUILD → New build: $NEW_BUILD"

# macOS BSD sed: -i '' for in-place edit (no backup file)
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"

# Verify all occurrences were updated
REMAINING=$(grep -c "CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};" "$PBXPROJ" || true)
if [ "$REMAINING" -gt 0 ]; then
  echo "❌ Some CURRENT_PROJECT_VERSION entries were not updated. Aborting."
  exit 1
fi

echo "   ✅ All CURRENT_PROJECT_VERSION entries updated to $NEW_BUILD"

# ─────────────────────────────────────────────────────────────
# ARCHIVE & UPLOAD
# ─────────────────────────────────────────────────────────────

echo ""
echo "🏗️  Archiving (build $NEW_BUILD)..."
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  $AUTH CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=RA9YY36MWN \
  2>&1 | grep -E "error:|ARCHIVE" | tail -3

[ -d "$ARCHIVE" ] || { echo "❌ Archive failed"; exit 1; }

echo ""
echo "📦 Exporting & uploading..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath "$EXPORT" $AUTH \
  2>&1 | grep -E "error:|Upload|EXPORT" | tail -5

# ─────────────────────────────────────────────────────────────
# POST-DEPLOY: COMMIT, TAG, NOTIFY
# ─────────────────────────────────────────────────────────────

echo ""
echo "📝 Committing build bump..."
cd "$REPO_ROOT"
git add "$PBXPROJ" CHANGELOG.md
git commit -m "chore: bump build to $NEW_BUILD"

echo "🏷️  Tagging build/$(echo $NEW_BUILD)..."
git tag "build/$NEW_BUILD"

echo "📤 Pushing commit and tag..."
git push origin main
git push origin "build/$NEW_BUILD"

echo ""
echo "📣 Sending Telegram notification..."
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "⚠️  Telegram notification skipped: bot token not configured"
else
  TELEGRAM_TEXT="🚀 ThePerch Build ${NEW_BUILD} uploaded to TestFlight (${LANE} lane). Should be available in ~5 minutes."
  TELEGRAM_RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="$TELEGRAM_TEXT" \
    -d parse_mode=Markdown)
  if echo "$TELEGRAM_RESPONSE" | grep -q '"ok":true'; then
    echo "✅ Telegram notification sent"
  else
    echo "⚠️  Telegram notification failed but deploy succeeded"
    echo "   Response: $TELEGRAM_RESPONSE"
  fi
fi

echo ""
echo "✅ Done. Build $NEW_BUILD will appear in TestFlight in ~5 minutes (${LANE} lane)."
