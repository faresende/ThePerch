# QUICKSTART.md - The Perch iOS App

## Prerequisites

- macOS with Xcode 15.0+
- Apple Developer account (for device builds)
- Supabase project credentials

## 5-Minute Setup

### 1. Open the Project

```bash
cd ThePerch/ios/ThePerch
xed .   # Opens in Xcode
```

### 2. Configure Supabase Credentials

Create `Sources/ThePerch/Config/Secrets.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SUPABASE_URL</key>
    <string>https://<YOUR-PROJECT-REF>.supabase.co</string>
    <key>SUPABASE_ANON_KEY</key>
    <string>your-anon-key-here</string>
</dict>
</plist>
```

**Important**: `Secrets.plist` must be in `.gitignore`. Never commit credentials.

### 3. Verify the Build

```bash
xcodebuild -scheme ThePerch -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### 4. Run on Simulator

In Xcode: select "ThePerch" scheme → choose an iOS 17+ simulator → press Cmd+R.

### 5. Run on Device

1. Open Xcode → Settings → Accounts → add your Apple ID
2. Select your team in the project's Signing & Capabilities tab
3. Connect your device → select it as the run destination → Cmd+R

## Architecture in 60 Seconds

```
Models/          Data structures (no UI, no network)
Services/        Supabase queries, EventKit sync
ViewModels/      @Observable state management
Views/           SwiftUI views (Cards/, Sections/, Components/, Theme/)
```

Data flows: **Supabase → Service → ViewModel → View** (all async/await, no callbacks).

## Key Files

| File | What it does |
|------|-------------|
| `ThePerchApp.swift` | Root: auth gate → MainTabView |
| `AppConfig.swift` | Supabase credential resolution |
| `Record.swift` | Core data model with all enums |
| `PerchTheme.swift` | Colors, fonts, spacing, card styles |
| `WidgetRouter.swift` | Maps records to card views |
| `HomeCardOrdering.swift` | Smart card ordering on Today tab |

## How to Add a New Card

1. Create `Views/Cards/MyCard.swift`
2. Use `cardStyle()` modifier for consistent styling
3. Add `DisplayHint` case in `Record.swift` if needed
4. Register in `WidgetRouter.swift`
5. Add to `HomeCardOrdering.swift` for Today feed placement

## How to Add a New Tab/Section

1. Create `Views/Sections/MySectionView.swift`
2. Create `ViewModels/MySectionViewModel.swift`
3. Insert section row in Supabase `sections` table
4. Add tab in `MainTabView.swift`

## Widget Extension

The widget extension (`ThePerchWidgets/`) includes:
- Home screen quick glance widget
- Lock screen widgets
- Live Activity for delivery tracking (Dynamic Island)

Widgets share types via `PerchSharedKit/` framework.

## Theme Quick Reference

| Token | Usage |
|-------|-------|
| `PerchTheme.background` | Main background |
| `PerchTheme.cardBackground` | Card surface (glass effect) |
| `PerchTheme.accent` | Amber accent for CTAs |
| `PerchTheme.Font.heading` | 18pt semibold |
| `PerchTheme.Spacing.medium` | 20pt standard spacing |
| `PerchTheme.Card.cornerRadius` | 16pt card corners |

## Testing

Unit tests are in `ThePerchTests/`:
- `RecordTests.swift` - Record decoding
- `DataPayloadsTests.swift` - Payload type validation
- `OrderModelsTests.swift` - Order/Shipment model tests
- `CalendarDecodingTests.swift` - Calendar event parsing
- `PerchFormattersTests.swift` - Date/number formatting

Run tests: `Cmd+U` in Xcode.
