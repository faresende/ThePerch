#!/bin/bash
set -euo pipefail

PROJECT="$HOME/Documents/Apps/ThePerch/ios/ThePerch/ThePerch.xcodeproj"
SCHEME="ThePerch"
ARCHIVE="/tmp/ThePerch.xcarchive"
EXPORT="/tmp/ThePerch-export"
EXPORT_OPTS="$HOME/Documents/Apps/ThePerch/.xcodebuildmcp/ExportOptions.plist"
KEY="$HOME/.openclaw/secrets/AuthKey_87UBF99Q64.p8"
KEY_ID="87UBF99Q64"
ISSUER="69a6de81-7c5a-47e3-e053-5b8c7c11a4d1"

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
