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
                  └─→ MainTabView (Horizontal Paging)
                     ├─ HomeView (Dashboard)
                     ├─ HealthView (Measurements)
                     ├─ DeliveriesView (Orders)
                     ├─ BookmarksView (Articles)
                     ├─ CalendarView (Events)
                     ├─ AdminView (Agent Status)
                     └─ LegalView (Documents)
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
    AuthViewModel      DashboardViewModel     SectionViewModel
    • signIn()         • sections             • records
    • signUp()         • homeWidgets          • loadRecords()
    • signOut()        • loadDashboard()      • search()
                       • reorderSections()    • togglePin()
                                              • setSortOrder()
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
├── Sections/ (Full-Screen Views)
│   ├── HomeView (dashboard overview)
│   ├── HealthView (measurements + chart)
│   ├── DeliveriesView (tracking)
│   ├── BookmarksView (search + filter)
│   ├── CalendarView (events)
│   ├── AdminView (agent status)
│   └── LegalView (documents)
│
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
