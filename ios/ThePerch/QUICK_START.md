# The Perch iOS App - Quick Start Guide

## What Was Built

A complete, production-ready SwiftUI UI for The Perch dashboard app. All views are fully functional with mock data and ready to be connected to the real Supabase backend.

## File Organization

```
Sources/ThePerch/
├── Views/                          # All new SwiftUI views
│   ├── Theme/PerchTheme.swift      # Design system colors, typography, spacing
│   ├── Cards/                      # Reusable card components (8 types)
│   ├── Helpers/                    # MockData.swift, WidgetRouter.swift
│   ├── Sections/                   # 7 full-screen section views
│   ├── Settings/SettingsView.swift
│   └── App/                        # Auth and main navigation
├── ThePerchApp.swift               # ✅ UPDATED - routes Auth/Dashboard
└── ContentView.swift               # ✅ UPDATED - now uses MainTabView
```

## How to Test

### In Xcode Preview Canvas
1. Open any view file in Xcode
2. Click the "Resume" button in the canvas panel
3. Preview live-updates as you edit
4. Every view has a working preview with mock data

### Build & Run
```bash
# Build the app
xcodebuild -scheme ThePerch -configuration Debug

# Run in simulator
xcode-select -p  # Verify Xcode is installed
# Then Cmd+R in Xcode to run
```

## App Flow

```
ThePerchApp
├─ if authenticated
│  └─ MainTabView (native tab shell)
│     ├─ TodayTab (dashboard overview)
│     ├─ HealthTab (health / nutrition / workouts)
│     ├─ HubTab (orders, bookmarks, calendar, travel)
│     ├─ SettingsTab (presented as a sheet)
│     └─ CaptureSheet (presented as a sheet)
│
└─ else
   └─ AuthView (sign in / sign up)
```

## Key Components

### PerchTheme
Centralized design system. Modify these constants to customize the app:
- Colors (adaptive light/dark)
- Typography scale
- Spacing values
- Card styling

**File:** `Views/Theme/PerchTheme.swift`

### Card Components (8 types)
All cards are reusable and self-contained:
1. **SingleValueCard** - Large number displays
2. **StatusListCard** - Status item lists
3. **TimelineCard** - Event timelines
4. **ChartCard** - Line charts
5. **BookmarkCard** - Bookmark display
6. **ChecklistCard** - Interactive checklists
7. **CostBreakdownCard** - Cost visualization
8. **CardContainer** - Generic wrapper

**Location:** `Views/Cards/`

### WidgetRouter
Intelligent dispatcher that converts `Record` objects into the correct card view based on their `DisplayHint` enum.

**File:** `Views/Helpers/WidgetRouter.swift`

**How it works:**
```swift
let record = Record(...)  // From API
WidgetRouter(record: record)  // Automatically renders correct card
```

### MockData
Comprehensive mock data for all card types. Replace with real data from Supabase.

**File:** `Views/Helpers/MockData.swift`

**Usage:**
```swift
let measurements = MockData.measurementRecords
let deliveries = MockData.deliveryRecords
let agents = MockData.agents
// etc.
```

## Connecting to Real Data

### Step 1: Use the shared dashboard models
The app now loads generic records through `DashboardViewModel`, then derives focused surfaces like Today, Health, and Hub from that shared state.

```swift
@Environment(DashboardViewModel.self) var dashboardViewModel

Task {
    await dashboardViewModel.loadDashboard()
}
```

### Step 2: Feed focused views from the shared model
Replace direct mock-data wiring with the relevant shared view model or derived records:

```swift
// Before
let measurements = MockData.measurementRecords

// After
@Environment(DashboardViewModel.self) var dashboardViewModel
let measurements = dashboardViewModel.healthRecords
```

### Step 3: Test with Real API
Just sign in with real credentials. The app will load actual data from Supabase.

## Customization

### Change Accent Color
Edit `PerchTheme.swift`:
```swift
static var accent: Color {
    Color(red: 0.20, green: 0.56, blue: 0.63, alpha: 1)  // Change this
}
```

### Change Card Corner Radius
Edit `PerchTheme.swift`:
```swift
enum Card {
    static let cornerRadius: CGFloat = 16  // Change to 8, 12, 20, etc.
}
```

### Change Spacing
All spacing uses the `PerchTheme.Spacing` enum:
```swift
PerchTheme.Spacing.small        // 12pt
PerchTheme.Spacing.medium       // 16pt
PerchTheme.Spacing.large        // 24pt
```

### Add New Card Type
1. Create new view in `Views/Cards/`
2. Add new `DisplayHint` case if needed
3. Add handling in `WidgetRouter.swift`

## Design Details

### Colors (Automatically Adapt to Light/Dark)
- **Background**: Very light gray ↔ Dark charcoal
- **Card**: White ↔ Dark gray
- **Text**: Dark ↔ Light
- **Accent**: Calm teal (unchanged)
- **Status**: Green (success), Orange (warning), Red (error)

### Typography
- Headlines: Semibold 17-28pt
- Body: Regular 17pt
- Captions: Regular 12-13pt
- All using system fonts (SF Pro Display)

### Spacing
8pt units for consistency:
- 2, 4, 8, 12, 16, 24, 32, 48px
- Cards: 16pt padding
- Sections: 24pt margins

## Features

✅ Light and dark mode (automatic)
✅ All SF Symbols icons
✅ Swift Charts integration
✅ Pull-to-refresh
✅ Empty states
✅ Loading states
✅ Error handling
✅ Search and filtering
✅ Settings view
✅ Sign in/sign up
✅ Responsive layout
✅ Preview blocks for every view

## Testing Checklist

- [ ] Run in light mode
- [ ] Run in dark mode
- [ ] Test pull-to-refresh
- [ ] Swipe between tabs
- [ ] Try search and filters
- [ ] Test settings view
- [ ] Check all preview blocks
- [ ] Test on iPhone 15 Pro
- [ ] Test on iPhone SE (small screen)
- [ ] Test on iPad (if needed)

## Documentation

- `VIEWS_BUILD_SUMMARY.md` - Detailed overview of all components
- `QUICK_START.md` - This file
- Each Swift file has inline comments

## Project Structure

```
ThePerch/
├── ios/ThePerch/
│   ├── Sources/ThePerch/
│   │   ├── Views/                    ← All new files here
│   │   ├── Models/                   ← Existing (unchanged)
│   │   ├── ViewModels/               ← Existing (unchanged)
│   │   ├── Services/                 ← Existing (unchanged)
│   │   ├── Config/                   ← Existing (unchanged)
│   │   ├── ThePerchApp.swift         ← UPDATED
│   │   └── ContentView.swift         ← UPDATED
│   └── Package.swift
```

## Next Steps

1. **Test with Preview Canvas**: Open any view and test the preview
2. **Build & Run**: Run on simulator to test interactions
3. **Connect Real Data**: Update to use actual Supabase records
4. **Customize Colors**: Adjust PerchTheme to match brand
5. **Add Animations**: SwiftUI animations can be added to card transitions
6. **Polish Details**: Add haptic feedback, navigation animations, etc.

## Support

For questions about specific components:
- `PerchTheme.swift` - Design system questions
- `WidgetRouter.swift` - Data-to-view mapping
- `MainTabView.swift` - Navigation structure
- Individual section views for section-specific features

## Build Info

- **iOS Deployment Target**: 17.0+
- **Swift Version**: 5.9+
- **UI Framework**: SwiftUI
- **Charts**: Swift Charts (built-in)
- **State Management**: @Observable (iOS 17+)
- **Architecture**: MVVM with environment objects

Happy coding! 🚀
