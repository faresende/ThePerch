#!/bin/bash
set -euo pipefail

PROJECT="$HOME/Documents/Apps/ThePerch/ios/ThePerch/ThePerch.xcodeproj"
SCHEME="ThePerch"
ARCHIVE="/tmp/ThePerch.xcarchive"
EXPORT="/tmp/ThePerch-export"
EXPORT_OPTS="$HOME/Documents/Apps/ThePerch/.xcodebuildmcp/ExportOptions.plist"
KEY="$HOME/.openclaw/secrets/AuthKey_SCRUBBED-APPLE-KEY-ID.p8"
KEY_ID="SCRUBBED-APPLE-KEY-ID"
ISSUER="00000000-0000-0000-0000-000000000000"

AUTH="-allowProvisioningUpdates -authenticationKeyPath $KEY -authenticationKeyID $KEY_ID -authenticationKeyIssuerID $ISSUER"

echo "🏗️  Archiving..."
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  $AUTH CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=RA9YY36MWN \
  2>&1 | grep -E "error:|ARCHIVE" | tail -3

[ -d "$ARCHIVE" ] || { echo "❌ Archive failed"; exit 1; }

echo "📦 Exporting & uploading..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath "$EXPORT" $AUTH \
  2>&1 | grep -E "error:|Upload|EXPORT" | tail -5

echo "✅ Done. Build will appear in TestFlight in ~5 minutes."
