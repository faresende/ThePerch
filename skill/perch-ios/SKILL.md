---
name: perch-ios
description: "Native iOS personal dashboard app built with SwiftUI. Covers building, running, architecture, widgets, and contributing."
version: 1.0.0
---

# perch-ios

## Trigger

Any task involving the The Perch iOS app: building, running, adding features, debugging UI issues, modifying views/viewmodels, or working with the SwiftUI frontend. Also triggered when discussing the app architecture, widget extensions, or theme system.

## What it does

The Perch is a native iOS personal dashboard app built with SwiftUI. It connects to a Supabase backend and displays health metrics, nutrition tracking, orders/deliveries, calendar events, bookmarks, workouts, and travel information in a card-based layout. The app features adaptive light/dark theming with a warm amber accent, pull-to-refresh, live activities for delivery tracking, and a widget extension for lock screen and home screen.

The app follows a strict MVVM architecture: Views observe ViewModels, ViewModels call Services, and Services query Supabase. All state management uses the modern `@Observable` macro (iOS 17+), and all async work uses `async/await` with no third-party reactive frameworks.

## Architecture

```
ThePerchApp (root, authentication gate)
  └─ MainTabView
      ├─ TodayTab    → HomeView    (daily dashboard with smart-ordered cards)
      ├─ HealthTab   → HealthView  (charts, metrics, nutrition)
      ├─ HubTab      → OrdersView, BookmarksView, CalendarView, TravelView
      └─ SettingsTab → SettingsView (profile, sign out)

Widget Extension:
  ├─ PerchQuickGlanceWidget  (home screen widget)
  ├─ DeliveryLiveActivity    (Live Activity for in-transit packages)
  └─ PerchLockScreenWidgets  (lock screen widgets)
```

### Data Flow

```
Supabase Backend
      │
      │ REST queries (anon key + user auth)
      ▼
SupabaseService (@MainActor singleton)
  ├─ fetchRecords()
  ├─ fetchAgents()
  ├─ fetchSections()
  └─ updatePin()
      │
      ▼
ViewModels (@Observable)
  ├─ DashboardViewModel  (sections, homeWidgets, loadDashboard)
  ├─ HomeViewModel       (today card feed)
  ├─ HealthViewModel     (health metrics)
  ├─ NutritionViewModel  (macro tracking)
  ├─ OrdersViewModel     (orders + shipments)
  ├─ TravelViewModel     (trip tracking)
  ├─ AdminViewModel      (agent status)
  └─ AuthViewModel       (sign in/out)
      │
      ▼
SwiftUI Views (@Environment injection)
```

### Project Structure

```
ios/ThePerch/Sources/ThePerch/
├── ThePerchApp.swift           # App entry point
├── Config/
│   ├── AppConfig.swift         # Supabase URL/key, Keychain migration
│   └── Secrets.plist           # (gitignored) API credentials
├── Models/
│   ├── Record.swift            # Record, RecordType, RecordCategory, DisplayHint enums
│   ├── OrderModels.swift       # Order, Shipment, OrderWithShipments structs
│   ├── NutritionModels.swift   # Meal, Macro tracking types
│   ├── DataPayloads.swift      # Typed payload structs (MeasurementData, DeliveryData, etc.)
│   ├── JSONValue.swift         # Recursive JSON enum for flexible data field
│   ├── Section.swift           # Section model
│   ├── Agent.swift             # Agent status model
│   ├── UserProfile.swift       # User profile model
│   └── TokenUsage.swift        # Cost tracking model
├── ViewModels/
│   ├── DashboardViewModel.swift  # Central data orchestrator
│   ├── HomeViewModel.swift       # Today tab card feed
│   ├── HealthViewModel.swift     # Health metrics aggregation
│   ├── NutritionViewModel.swift  # Macro/calorie tracking
│   ├── OrdersViewModel.swift     # Order + shipment fetching
│   ├── TravelViewModel.swift     # Trip management
│   ├── AdminViewModel.swift      # Agent health monitoring
│   └─ AuthViewModel.swift        # Authentication state
├── Views/
│   ├── App/                      # Root navigation
│   │   ├── MainTabView.swift     # Tab bar shell
│   │   ├── TodayTab.swift        # Home/daily feed
│   │   ├── HealthTab.swift       # Health section container
│   │   ├── HubTab.swift          # Orders, bookmarks, calendar hub
│   │   ├── SettingsTab.swift     # Settings sheet
│   │   ├── AuthView.swift        # Sign in/up
│   │   ├── SearchView.swift      # Universal search
│   │   └── CardGalleryView.swift # Card component gallery
│   ├── Sections/                 # Full-screen section views
│   │   ├── HomeView.swift
│   │   ├── HealthView.swift
│   │   ├── WorkoutView.swift
│   │   ├── OrdersView.swift
│   │   ├── BookmarksView.swift
│   │   ├── CalendarView.swift
│   │   ├── TravelView.swift
│   │   ├── NutritionView.swift
│   │   ├── AdminView.swift
│   │   └── OnboardingView.swift
│   ├── Cards/                    # Reusable card components
│   │   ├── CardContainer.swift
│   │   ├── SingleValueCard.swift
│   │   ├── ChartCard.swift
│   │   ├── DeliveryCard.swift
│   │   ├── DeliveryHomeCard.swift
│   │   ├── BookmarkCard.swift
│   │   ├── EventCard.swift
│   │   ├── ChecklistCard.swift
│   │   ├── HealthSummaryCard.swift
│   │   ├── NutritionHomeCard.swift
│   │   ├── MealCard.swift
│   │   ├── MacrosCard.swift
│   │   ├── CaloriesCard.swift
│   │   ├── WorkoutCard.swift
│   │   ├── OrderCard.swift
│   │   ├── TravelHomeCard.swift
│   │   ├── WeatherCompactCard.swift
│   │   ├── AgentStatusCard.swift
│   │   ├── EmailSummaryCard.swift
│   │   ├── PaperlessCard.swift
│   │   ├── CostBreakdownCard.swift
│   │   └── UniversalCard/        # Universal card system
│   ├── Components/               # Shared UI components
│   │   ├── NewCardStyle.swift
│   │   ├── GlassTabBar.swift
│   │   ├── LiquidGlassTabBar.swift
│   │   ├── SectionNavigator.swift
│   │   ├── EmptyStateView.swift
│   │   └── ErrorBanner.swift
│   ├── Theme/
│   │   ├── PerchTheme.swift      # Colors, typography, spacing, card styling
│   │   └── PerchFormatters.swift # Date/number formatting
│   └── Helpers/
│       ├── WidgetRouter.swift    # Record → Card dispatcher
│       ├── MockData.swift        # Preview data
│       ├── HomeCardOrdering.swift # Smart card ordering
│       ├── HomeCardHeader.swift
│       ├── SparklineView.swift
│       └── ShimmerEffect.swift
└── ThePerchWidgets/              # Widget extension target
    ├── PerchQuickGlanceWidget.swift
    ├── DeliveryLiveActivity.swift
    ├── PerchLockScreenWidgets.swift
    └── ThePerchWidgets.swift

ios/ThePerch/PerchSharedKit/      # Shared types between app and widgets
    └── DeliveryActivityAttributes.swift
```

### Theme System (PerchTheme.swift)

| Token | Dark | Light | Usage |
|-------|------|-------|-------|
| `background` | `#121213` | `#F8F7F5` | Main background |
| `cardBackground` | `#191A1B 70%` | `#FFFFFF 80%` | Card surfaces (glass) |
| `textPrimary` | `#F2F0EB` | `#1A1A1A` | Headlines, body text |
| `textSecondary` | `#A29D95` | `#6B6B70` | Metadata, labels |
| `accent` | `#F2B04A` | `#C8840A` | Amber accent (CTAs, highlights) |
| `success` | `#38C97A` | `#1D8A3C` | Positive states |
| `warning` | `#F0A24A` | `#C47F0A` | Warning states |
| `error` | `#E85A5A` | `#C42B2B` | Error states |

**Typography scale**: `micro` (11pt), `caption` (13pt), `body` (15pt), `heading` (18pt), `title` (24pt), `display` (34pt), `largeTitle` (40pt). Numeric variants use `.rounded` design.

**Spacing scale**: `xxxSmall` (3pt) → `xxxLarge` (80pt). Cards use 16pt corner radius, 20pt padding.

### Widget Extension Architecture

The app includes a WidgetKit extension with three components:

1. **PerchQuickGlanceWidget**: Home screen widget showing top cards
2. **DeliveryLiveActivity**: Live Activity using ActivityKit for real-time delivery tracking (Dynamic Island + lock screen)
3. **PerchLockScreenWidgets**: Compact lock screen widgets

Live Activities use `DeliveryActivityAttributes` from `PerchSharedKit` (shared framework). The activity displays carrier, tracking number, status, and ETA. It's started when a shipment transitions to `in_transit` or `out_for_delivery`.

## Data Schema

The iOS app reads from these Supabase tables (see [perch-supabase](../perch-supabase/SKILL.md) for full schema):

- `dashboard_records`: All card data
- `records`: Structured data with `RecordCategory` enum
- `orders` + `shipments`: Commerce tracking (OrdersView)
- `sections`: Tab configuration and ordering
- `agents`: Agent health status (AdminView)

Key iOS models:
- `Record`: Maps to `dashboard_records` with typed `decodeData<T>()` accessor
- `Order`, `Shipment`, `OrderWithShipments`: Commerce models with `effectiveStatus` and `manualDeliveredAt` support
- `RecordType`: 18 record types (measurement, meal, delivery, event, bookmark, workout_session, etc.)
- `RecordCategory`: 9 categories (health, nutrition, workouts, deliveries, calendar, admin, legal, bookmarks, travel)
- `DisplayHint`: 12 hints (chart, single_value, progress_gauge, macros_bar, meal_log, etc.)

## Setup

See [QUICKSTART.md](./QUICKSTART.md) for step-by-step setup instructions.

### Prerequisites

- Xcode 15.0+ (iOS 17.0+ deployment target)
- Apple Developer account (for device builds)
- Supabase project with migrations applied (see perch-supabase)

### Configuration

1. Create `Secrets.plist` with `SUPABASE_URL` and `SUPABASE_ANON_KEY`
2. Or configure via Keychain at runtime (production flow)
3. The `AppConfig` singleton handles credential resolution: Keychain → Secrets.plist → Info.plist → env vars

### Running

```bash
# Open in Xcode
cd ios/ThePerch
xed .

# Build for simulator
xcodebuild -scheme ThePerch -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'

# Build for device (requires provisioning profile)
xcodebuild -scheme ThePerch -configuration Debug -destination 'platform=iOS,name=Your iPhone'
```

## Maintenance

### Adding a New Card to the Dashboard

1. Create a new Swift file in `Views/Cards/` (e.g., `MyNewCard.swift`)
2. Follow the card pattern: use `CardContainer` or `cardStyle()` modifier
3. Add a new `DisplayHint` case if needed (update `DisplayHint` enum in `Record.swift`)
4. Register the card in `WidgetRouter.swift` to dispatch records with the matching hint
5. Add the card to `HomeCardOrdering.swift` for smart placement in the Today feed

### Adding a New Section/Tab

1. Create a section view in `Views/Sections/`
2. Create a corresponding ViewModel in `ViewModels/`
3. Add a row to the `sections` table in Supabase (or use `provision_new_user`)
4. Add the tab to `MainTabView.swift`

### Debugging

- Use `MockData.swift` for SwiftUI previews without Supabase
- Check `AppConfig.isMisconfigured` if the app shows onboarding unexpectedly
- Use `DecodingCache.shared.clear()` if cached payloads seem stale
- Check `PerchMotion.prefersReduced` for animation issues (respects system setting)

### Common Issues

- **Build errors after schema changes**: Clean build folder (Cmd+Shift+K), regenerate `Record.swift` enums if needed
- **Cards not appearing**: Verify `display_hint` matches what `WidgetRouter` expects
- **Empty sections**: Check that `sections.is_visible = true` for the user and records exist with matching category
