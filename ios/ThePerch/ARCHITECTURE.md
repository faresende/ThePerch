# The Perch Architecture & Data Flow

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     ThePerchApp                         │
│              (Root - Authentication)                    │
└──────────────┬──────────────────────────────────────────┘
               │
               ├─ isAuthenticated = false
               │  └─→ AuthView (Sign In/Up)
               │
               └─ isAuthenticated = true
                  └─→ MainTabView (native tab shell)
                     ├─ TodayTab (home / daily dashboard)
                     ├─ HealthTab (health, nutrition, workouts)
                     ├─ HubTab (orders, bookmarks, calendar, travel)
                     ├─ SettingsTab (sheet)
                     └─ CaptureSheet (sheet)
```

## Data Flow Architecture

```
┌──────────────────────────────────────────────────────┐
│                 Supabase Backend                     │
│  (Records, Agents, Sections, HomeWidgets, etc.)    │
└───────────────────┬────────────────────────────────┘
                    │
                    │ Queries
                    ↓
        ┌──────────────────────────┐
        │  SupabaseService         │
        │  (@MainActor singleton)  │
        │  ├─ fetchRecords()       │
        │  ├─ fetchAgents()        │
        │  ├─ fetchSections()      │
        │  └─ updatePin()          │
        └────────────┬─────────────┘
                     │
         ┌───────────┴───────────┬──────────────────┐
         │                       │                  │
         ↓                       ↓                  ↓
    AuthViewModel      DashboardViewModel      Focused view models
    • signIn()         • sections              • HomeViewModel
    • signUp()         • homeWidgets           • HealthViewModel
    • signOut()        • loadDashboard()       • OrdersViewModel
                       • reorderSections()     • TravelViewModel
         │                       │                  │
         └───────────┬───────────┴──────────────────┘
                     │
                     ↓
            ┌─────────────────────┐
            │ SwiftUI Views       │
            │ @Environment inject │
            └─────────────────────┘
```

## View Layer Architecture

```
Views/
├── Theme/
│   └── PerchTheme.swift
│       ├── Colors (adaptive light/dark)
│       ├── Typography scale
│       ├── Spacing system
│       └── Card styling constants
│
├── Cards/ (Reusable Components)
│   ├── CardContainer (generic wrapper)
│   ├── SingleValueCard
│   ├── StatusListCard
│   ├── TimelineCard
│   ├── ChartCard (with Swift Charts)
│   ├── BookmarkCard
│   ├── ChecklistCard
│   └── CostBreakdownCard
│
├── Helpers/
│   ├── MockData.swift (for previews)
│   └── WidgetRouter.swift (Record → Card dispatcher)
│
├── Sections/ (Legacy / supporting full-screen views)
│   ├── HomeView (dashboard overview)
│   ├── HealthView (measurements)
│   ├── OrdersView (tracked deliveries / orders)
│   ├── BookmarksView (search + filter)
│   ├── CalendarView (events)
│   ├── AdminView (agent status)
│   └── LegalView (documents)

├── Settings/
│   └── SettingsView (profile, prefs, sign out)
│
└── App/
    ├── AuthView (sign in/up screen)
    └── MainTabView (root navigation)
```

## Key Features

- ✅ Adaptive light/dark mode
- ✅ 8 reusable card types
- ✅ 7 full-screen sections
- ✅ Swift Charts integration
- ✅ Pull-to-refresh
- ✅ Search & filtering
- ✅ Empty & error states
- ✅ Settings view
- ✅ Authentication flow
- ✅ Responsive design

## Total Files Created: 21

- **Theme:** 1
- **Cards:** 8
- **Helpers:** 2
- **Sections:** 7
- **Settings:** 1
- **App:** 2

All production-ready with previews and comprehensive documentation.
