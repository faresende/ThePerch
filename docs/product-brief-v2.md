# ThePerch v2 Product Brief
*Date: 2026-04-06*
*Author: Bancada (/ceo mode)*
*For: Claudinho (execution planning)*

## Vision

Transform ThePerch from a category-based swipe-through utility into a context-aware personal dashboard with bottom tab navigation, a modern visual system (minimalism + selective Liquid Glass), and a serious reliability/performance pass.

## Current State

- **Navigation:** 9 horizontal swipe sections with a floating pill bar at the top (Home, Health, Nutrition, Workouts, Deliveries, Calendar, Bookmarks, Admin, Travel)
- **Problems:**
  - Too many top-level sections; unclear boundaries (Health vs Nutrition vs Workouts)
  - Travel and Admin occupy permanent space despite being rarely used
  - Bookmarks (Karakeep) tab is broken/unreliable
  - No bottom tab bar (feels dated for iOS 2025+)
  - Visual system needs modernization
  - Performance and resilience are not systematically addressed

## New Information Architecture

### Bottom Tab Bar (4 tabs)

```
[Today] [Health] [Hub] [Settings]
```

### Tab Definitions

#### Today (smart front page)
The live dashboard. What needs attention now. Dynamic, contextual, time-aware.

Contents:
- Greeting + date header + settings gear
- Quick Glance chip strip (next event, active deliveries count, weather/sleep)
- Health summary card (compact)
- Nutrition card (today's intake)
- Calendar today + tomorrow
- Deliveries card (only when active deliveries exist)
- Travel card (only when trip is upcoming/active)
- Weather compact card
- Email summary card
- Medications card

Card ordering follows time-of-day logic (existing `HomeCardOrdering`). Travel and Deliveries are contextual -- they appear/hide based on data presence.

**Migration:** Evolves from current `HomeView`. Most of the logic already exists. Key change: move from swipe-page to scroll-only within the tab.

#### Health (everything body)
Collapses current Health, Nutrition, and Workouts into one coherent destination.

Top-level segmented control:
```
[Overview] [Workouts] [Nutrition]
```

**Overview segment:**
- Body metrics (weight, body fat %, skeletal muscle)
- Sleep score + readiness
- Trend charts over time

**Workouts segment:**
- Weekly volume card
- Recent sessions feed (full workout log with expandable details)
- Personal records card
- This is where the workout log lives. One tap from tab bar.

**Nutrition segment:**
- Daily summary bar
- Macros card
- Calories card
- Meal log / meal cards

**Migration:** Combines `HealthView`, `WorkoutView`, `NutritionView` into a single container with segmented navigation. Each segment reuses existing view components.

#### Hub (operational tools)
Everything you need to manage. Not metrics -- actions and references.

Contents (vertical scroll, section-based):
- **Deliveries** (active on top, delivered below) -- reuses `OrdersView` / `DeliveriesView`
- **Bookmarks** (Karakeep + Paperless with search + tags) -- reuses `BookmarksView`
- **Calendar** (full calendar view) -- reuses `CalendarView`
- **Travel** (when active, pinned to top of Hub) -- reuses `TravelView`

When no travel is active, Travel section is hidden entirely.

**Migration:** New container view that composes existing section views with section headers and collapsible areas.

#### Settings (configuration)
All admin, config, and integration management.

Contents:
- Account / profile
- Integrations (Supabase, Karakeep, Paperless, health sources, etc.)
- Admin tools (moved from current `AdminView`)
- Preferences (theme, notifications, etc.)
- Debug / advanced
- About / version

**Migration:** Evolves from current `SettingsView` + absorbs `AdminView`.

### What Gets Removed from Top-Level Nav
- Health (absorbed into Health tab > Overview)
- Nutrition (absorbed into Health tab > Nutrition)
- Workouts (absorbed into Health tab > Workouts)
- Travel (contextual in Today + Hub, not permanent)
- Admin (moved to Settings)
- Calendar (moved to Hub)
- Bookmarks (moved to Hub)

### Key Access Patterns (user stories)

| I want to...                  | Path                              |
|-------------------------------|-----------------------------------|
| See what's happening now      | Today tab (default)               |
| Check my workout log          | Health tab → Workouts segment     |
| Log what I ate                | Health tab → Nutrition segment    |
| Check a delivery              | Hub tab → Deliveries section      |
| Find a saved bookmark         | Hub tab → Bookmarks section       |
| See my calendar               | Hub tab → Calendar section        |
| Check travel details          | Hub tab → Travel (when active)    |
| Change settings / admin       | Settings tab                      |
| See body metrics over time    | Health tab → Overview segment     |

## Visual Direction

### Principles
- **Chrome = glass, Content = crisp, Data = stable**
- Large, breathable spacing
- Fewer boxes, softer hierarchy
- Translucent surfaces only for: navigation bar, tab bar, floating controls, section headers
- Cards that feel lighter -- depth from layering, not heavy borders
- Stronger typography rhythm
- Less color, more semantic emphasis
- Motion that feels responsive and calm

### Liquid Glass Usage
- **YES:** Bottom tab bar, navigation header, floating action buttons, modal sheets
- **SELECTIVE:** Section headers within scrollable content, card backgrounds on hover/press
- **NO:** Individual metric cards, data visualizations, text content areas

### Design System Updates Needed
- Update `PerchTheme` with new spacing scale
- New card style (lighter, less bordered)
- Bottom tab bar component with glass material
- Updated type scale (larger titles, more hierarchy)
- Remove top pill bar navigation entirely
- New segmented control style for Health sub-sections

## Reliability Fixes

### Karakeep Bookmarks
- Diagnose why the Bookmarks tab is broken (data layer? API? rendering?)
- Ensure proper loading, empty, and error states
- Move to Hub tab with full search/filter functionality
- Test with real Karakeep data

### General Reliability
- Every section/module needs: loading state, empty state, error state, offline state
- No dead tabs or broken sections
- Graceful degradation when one data source fails (others still work)
- Retry strategies for flaky integrations

## Performance Pass

### Startup
- Faster cold launch
- Predictable first paint
- Skeleton/loading states that feel intentional (already partially exists)

### Data
- Parallel fetch where safe
- Smarter caching (already has `CacheService`, audit effectiveness)
- Stale-while-revalidate behavior
- Retry strategy for flaky integrations

### UI
- Lighter view hierarchies (audit LazyVStack usage)
- Reduce layout thrash
- Avoid expensive redraw patterns
- Profile with Instruments

### Observability
- Clearer logging for integration failures
- Identify slow screens
- Track fetch times per data source

## Implementation Tracks

### Track 1: Navigation & IA
- Replace horizontal swipe + pill bar with bottom TabView
- Create 4 tab containers: TodayTab, HealthTab, HubTab, SettingsTab
- Wire existing views into new containers
- Add segmented control to HealthTab

### Track 2: Visual System
- Update PerchTheme (spacing, typography, colors)
- New card styles (lighter)
- Glass materials for chrome elements
- Bottom tab bar styling
- Remove old pill bar navigation

### Track 3: Reliability
- Fix Karakeep bookmarks
- Audit all sections for missing states
- Add empty/error/loading/offline states everywhere
- Test integration failure scenarios

### Track 4: Performance
- Profile startup time
- Audit fetch patterns
- Optimize caching
- Profile render performance
- Reduce unnecessary redraws

## Migration Notes

### Files to Modify/Replace
- `MainTabView.swift` → complete rewrite (bottom TabView instead of horizontal pager)
- `SectionNavigator.swift` → remove (replaced by bottom tab bar)
- `HomeView.swift` → evolve into TodayTab content
- `HealthView.swift` → becomes HealthTab > Overview
- `WorkoutView.swift` → becomes HealthTab > Workouts
- `NutritionView.swift` → becomes HealthTab > Nutrition
- `AdminView.swift` → absorbed into SettingsTab
- `BookmarksView.swift` → moved into HubTab
- `OrdersView.swift` / `DeliveriesView.swift` → moved into HubTab
- `CalendarView.swift` → moved into HubTab
- `TravelView.swift` → conditional in Today + HubTab

### Files to Create
- `TodayTab.swift` (or rename HomeView)
- `HealthTab.swift` (container with segmented control)
- `HubTab.swift` (container with sections)
- `SettingsTab.swift` (expanded from current SettingsView)
- Updated `PerchTheme` extensions for new visual system

### Data Layer
- No Supabase schema changes needed
- Section visibility logic changes (sections are no longer top-level nav)
- `DashboardViewModel` stays as single-fetch source of truth
- `OrdersViewModel` stays independent

## Open Questions for Claudinho
1. Should Hub sections be collapsible or always expanded?
2. Should Health segments use iOS-native segmented control or custom pills?
3. Should Today cards link directly into Health/Hub sub-sections on tap?
4. Priority order: Navigation first? Visual system first? Both in parallel?

## Success Criteria
- App loads to Today tab in < 1 second
- Workout log is reachable in 1 tap from any screen
- Deliveries are reachable in 1 tap from any screen
- No broken/dead sections
- Every section handles loading, empty, error, and offline gracefully
- Visual system feels modern, quiet, and premium
- Bottom tab bar with Liquid Glass material
