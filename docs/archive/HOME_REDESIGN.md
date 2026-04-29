# ThePerch Home Screen Redesign

**Date:** March 8, 2026  
**Authors:** VP Product, VP Design, VP Engineering (brainstorm session)  
**Status:** Draft — ready for review

---

## Executive Summary

The Home screen should be a **live, always-on version of Claudinho's morning briefing**. Today's DailyBriefCard is a good start but it's a single monolithic card that shows a static snapshot. The redesign breaks it into independent, real-time cards — each fed by Supabase realtime subscriptions — that adapt their content and priority based on time of day. Health stays at the top. Calendar data bugs get fixed. New modules (emails, macros, medications) join the lineup.

---

## Part 1: VP Product — Information Architecture

### 1.1 Module Inventory

Every module maps 1:1 to a section of the morning briefing, plus new live-only modules:

| # | Module | Briefing Section | Priority | Category |
|---|--------|-----------------|----------|----------|
| 1 | **Health Summary** | Sleep + Readiness + Activity | Always top | health |
| 2 | **Nutrition/Macros** | Yesterday's nutrition (AM) / Today's live (PM) | High | health |
| 3 | **Calendar — Today** | Today's events | High | calendar |
| 4 | **Calendar — Tomorrow** | Tomorrow preview (evening brief) | Medium (rises in PM) | calendar |
| 5 | **Active Deliveries** | Deliveries section | Medium (rises when out-for-delivery) | deliveries |
| 6 | **Medications** | 💊 section | High (morning) / Low (after taken) | health |
| 7 | **Weather** | Weather section | Medium (morning) | NEW — needs data |
| 8 | **Important Emails** | Not in briefing today | Medium | NEW — needs data |
| 9 | **Body Composition** | Weekly/on-demand in briefing | Low (on-demand) | health |
| 10 | **Quick Actions** | N/A (app-only) | Persistent | N/A |

### 1.2 Priority Ordering by Time of Day

The card stack reorders dynamically. Here's the priority at each period:

**Morning (06:00–11:59)**
1. Health Summary (sleep score, duration, HRV, readiness)
2. Medications (has the scar cream been applied? weekly meds on Fridays?)
3. Calendar — Today (full day view)
4. Weather (do I need a jacket?)
5. Active Deliveries
6. Nutrition — Yesterday's recap
7. Important Emails

**Afternoon (12:00–16:59)**
1. Calendar — Today (remaining events, what's next?)
2. Nutrition — Live (calories consumed so far, macros progress)
3. Active Deliveries (out-for-delivery items get FEATURED)
4. Health Summary (collapses to compact — score only)
5. Important Emails

**Evening (17:00–21:59)**
1. Nutrition — Live (end-of-day progress, how much budget left?)
2. Calendar — Tomorrow (preview)
3. Active Deliveries
4. Health Summary (compact)
5. Body Composition (if weigh-in today)

**Night (22:00–05:59)**
1. Calendar — Tomorrow (top 2 events)
2. Health Summary (compact)
3. Nutrition — Today's final tally
4. Deliveries (muted unless out-for-delivery)

### 1.3 Data Requirements Per Module

#### Health Summary Card
- **Data:** sleep_duration, deep_sleep, avg_sleep_hrv, lowest_sleep_hr, readiness_score, sleep_score, activity_score
- **Source:** `dashboard_records` WHERE `category = 'health'` AND `type = 'measurement'`
- **Pushed by:** BioChecha (via Oura API → Supabase push, first interaction of day)
- **Empty state:** "Waiting for Oura data..." with a bed icon
- **Refresh:** Realtime subscription + pull-to-refresh

#### Nutrition/Macros Card
- **Data:** daily_calories (value + target), daily macros (protein/carbs/fat + targets)
- **Source:** `dashboard_records` WHERE `display_hint IN ('progress_gauge', 'macros_bar')` AND `context/date = today`
- **Pushed by:** BioChecha (after every meal log)
- **Empty state:** "No meals logged yet — log your first meal!" with fork.knife icon
- **Refresh:** Realtime (BioChecha pushes after each meal → record INSERT/UPDATE triggers UI refresh)
- **Key feature:** Calorie ring fills up through the day. Turns red if over target.

#### Calendar — Today
- **Data:** EventData records with `start` date = today
- **Source:** `dashboard_records` WHERE `category = 'calendar'` AND `type = 'event'`
- **Pushed by:** Claudinho (morning briefing push, or dedicated calendar sync agent)
- **Empty state:** "No events today — enjoy your free time 🎉"
- **Key feature:** Shows time-relative info ("in 45 min", "now", "2h ago")

#### Calendar — Tomorrow
- **Data:** EventData records with `start` date = tomorrow
- **Source:** Same table, filtered by tomorrow's date
- **Pushed by:** Same agent, must push tomorrow's events alongside today's
- **Empty state:** "Tomorrow is clear"
- **🐛 BUG: Currently shows "No events" even when events exist — see Part 3**

#### Active Deliveries
- **Data:** DeliveryData records with status ≠ delivered/cancelled
- **Source:** `dashboard_records` WHERE `category = 'deliveries'` AND `type = 'delivery'`
- **Pushed by:** Entregas agent (nightly delivery check at 03:00)
- **Empty state:** "No active deliveries" (hide card entirely when empty)
- **Key feature:** Each delivery is its own sub-card with carrier, items, status, ETA

#### Medications Card (NEW)
- **Data:** Medication checklist for today
- **Source:** NEW — needs `type = 'checklist'` record with `category = 'health'` and title "Medications"
- **Pushed by:** Claudinho (daily, as part of morning briefing push)
- **Content:** Scar cream (schedule-aware: every 2 days → alternate days → daily), weekly meds (Fridays only)
- **Empty state:** "No medications today ✓"
- **Interaction:** Tap to mark as taken (updates record via Supabase)

#### Weather Card (NEW)
- **Data:** Current conditions + day forecast
- **Source:** NEW — needs a weather record type OR embed wttr.in data in a measurement record
- **Pushed by:** Claudinho (morning briefing push)
- **Empty state:** "Weather unavailable"
- **Lightweight:** Compact single-row card. Icon + temp + conditions + rain probability.

#### Important Emails Card (NEW)
- **Data:** Flagged/urgent email subjects + senders
- **Source:** NEW — needs `type = 'text_note'` OR new `type = 'email_summary'` with `category = 'admin'`
- **Pushed by:** Claudinho (heartbeat checks, 2-4x daily)
- **Empty state:** "Inbox clear ✓" (or hide card)
- **Content:** Top 3 urgent/flagged emails: sender, subject, age
- **Interaction:** Tap opens email in Fastmail app (deep link)

#### Body Composition Card
- **Data:** Latest weight, skeletal muscle, body fat mass, body fat %
- **Source:** `dashboard_records` WHERE `category = 'health'` AND metrics = weight/smm/bfm/bf%
- **Pushed by:** BioChecha (after InBody scan)
- **Empty state:** "No recent weigh-in"
- **Visibility:** Only shows on days with a new weigh-in, or in compact form showing last reading

### 1.4 Morning Briefing Relationship

| Briefing Section | Dashboard Card | Relationship |
|-----------------|---------------|--------------|
| Sleep & Recovery | Health Summary | Live version — updates if Oura recalculates |
| Calendar | Today + Tomorrow | Live — events can be added/changed after briefing |
| Deliveries | Active Deliveries | Live — status changes through the day |
| Medications | Medications | Interactive — can mark as taken |
| Weather | Weather | Static (pushed once in AM), could refresh |
| Nutrition (yesterday) | Nutrition (yesterday AM / today PM) | Evolves: morning shows yesterday, afternoon+ shows live today |
| Not in briefing | Important Emails | Dashboard-only addition |
| Not in briefing | Body Composition | Dashboard-only (on weigh-in days) |

The dashboard **complements** the briefing. The briefing is a snapshot sent at ~7:30 AM. The dashboard is the always-current version that keeps updating as the day progresses.

---

## Part 2: VP Design — Visual & Interaction Design

### 2.1 Design Principles

1. **Glanceable first, detailed on demand** — every card has a compact state showing the most important number/status. Tap to expand.
2. **Dark-first** — all designs target the dark theme. Light mode is a secondary concern.
3. **Alive, not busy** — subtle indicators of liveness (last-updated timestamps, gentle pulse on active deliveries) without creating visual noise.
4. **Morning brief → Live dashboard transition** — the top of the screen evolves through the day. Not a jarring switch, but a gradual shift in content priority.

### 2.2 Card Hierarchy & Visual Weight

Three visual tiers:

- **Hero Card** (1 at a time): Full-width, taller, subtle accent border. Health Summary in morning, Nutrition in evening.
- **Standard Cards**: Full-width, standard height. Calendar, Deliveries, Emails.
- **Compact Cards**: Half-width or single-row. Weather, Medications, Quick Actions.

### 2.3 Time-of-Day Visual Transition

Replace the binary "Morning Brief / Evening Brief" toggle with a smooth ambient shift:

- **Morning (06–12):** Header icon = `sun.horizon.fill`, accent tint warm gold (#FFB74D)
- **Afternoon (12–17):** Header icon = `sun.max.fill`, accent tint bright blue (#42A5F5)
- **Evening (17–22):** Header icon = `moon.haze.fill`, accent tint soft purple (#AB47BC)
- **Night (22–06):** Header icon = `moon.stars.fill`, accent tint deep indigo (#5C6BC0)

The greeting already adapts ("Good morning/afternoon/evening/night"). The ambient color subtly tints the top card's border and the Quick Glance bar.

### 2.4 Card Designs (Detailed Mockup Descriptions)

#### Health Summary Card (Hero — Morning)

```
┌─────────────────────────────────────────────┐
│  🛏️ SLEEP & RECOVERY          Updated 5m ago │
│─────────────────────────────────────────────│
│                                             │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐   │
│  │ 7h30 │  │ 1h45 │  │  42  │  │  85  │   │
│  │sleep │  │ deep │  │ HRV  │  │ready │   │
│  │      │  │      │  │  ms  │  │score │   │
│  └──────┘  └──────┘  └──────┘  └──────┘   │
│                                             │
│  ┌─ Sleep Score ────────── 82 ─── Good ──┐ │
│  │ ████████████████████░░░░░░░           │ │
│  └──────────────────────────────────────┘ │
│                                             │
│  ┌─ Activity ───────── 650 cal ── 8.2k ──┐ │
│  │ steps                                  │ │
│  └──────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

- Four metric pills in a row: sleep duration, deep sleep, HRV, readiness score
- Below: sleep score as a horizontal progress bar (0–100)
- Below: activity compact row (active calories + steps)
- Compact state (afternoon+): Just the four pills, no bars
- Colors: Readiness score pill uses green (85+), yellow (70-84), red (<70)

#### Nutrition/Macros Card

```
┌─────────────────────────────────────────────┐
│  🍽️ NUTRITION                  Updated 2m ago│
│─────────────────────────────────────────────│
│                                             │
│      ┌─────────────┐                       │
│      │    1,847     │   Target: 3,400      │
│      │   ━━━━━━━    │   Remaining: 1,553   │
│      │    kcal      │                       │
│      └─────────────┘                       │
│                                             │
│  Protein ████████████░░░░░  142g / 180g    │
│  Carbs   ██████████░░░░░░░  245g / 386g    │
│  Fat     ███████░░░░░░░░░░   62g / 110g    │
│                                             │
└─────────────────────────────────────────────┘
```

- Central calorie ring (circular progress) showing consumed / target
- Three horizontal macro bars below (protein=blue, carbs=orange, fat=yellow)
- Each bar shows current/target with percentage fill
- Calorie ring turns red when >110% of target
- Protein bar pulses green when target hit
- Compact state: Single row — "1,847 / 3,400 kcal • P: 79% C: 63% F: 56%"

#### Calendar — Today Card

```
┌─────────────────────────────────────────────┐
│  📅 TODAY                        3 events    │
│─────────────────────────────────────────────│
│                                             │
│  ● 09:00  Team standup             in 45m  │
│  ○ 11:30  Lunch with Marco         in 3h   │
│  ○ 15:00  Dentist                  in 6h   │
│                                             │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│  ✓ 08:00  Morning run              done    │
│                                             │
└─────────────────────────────────────────────┘
```

- Upcoming events: filled circle (●), accent color
- Next event: slightly larger text, bold time
- Past events: muted, checkmark, strikethrough optional
- Location shown as secondary line if present
- Tap event → detail sheet (full description, location, notes)
- "in Xm/Xh" badges right-aligned, using relative time
- Compact state (when not primary): Top 2 upcoming events only

#### Calendar — Tomorrow Card

```
┌─────────────────────────────────────────────┐
│  📅 TOMORROW                     2 events    │
│─────────────────────────────────────────────│
│                                             │
│  ○ 10:00  Doctor appointment               │
│  ○ 14:30  Call with contractor              │
│                                             │
└─────────────────────────────────────────────┘
```

- Simpler than Today card — no relative times, no past events
- Only shows in evening/night periods (17:00+) at standard priority
- Earlier in the day: hidden unless user scrolls to it

#### Active Deliveries Card

```
┌─────────────────────────────────────────────┐
│  📦 DELIVERIES                   2 active    │
│─────────────────────────────────────────────│
│                                             │
│  ┌─────────────────────────────────────────┐│
│  │ 🟢 OUT FOR DELIVERY              ETA 2h ││
│  │ CTT • Skincare products                 ││
│  │ ○───────────────●──○                    ││
│  │ shipped    in transit   delivered        ││
│  └─────────────────────────────────────────┘│
│                                             │
│  ┌─────────────────────────────────────────┐│
│  │ 🟡 IN TRANSIT                  ETA Mar 10││
│  │ DHL • USB-C Hub                         ││
│  │ ○──────●────────○──○                    ││
│  └─────────────────────────────────────────┘│
│                                             │
└─────────────────────────────────────────────┘
```

- Each delivery is a sub-card with its own progress tracker
- Status dot: 🟢 out for delivery, 🟡 in transit, ⚪ ordered/processing
- Mini progress bar showing shipment stages
- Tap → opens tracking URL in Safari
- "Out for delivery" items have a subtle pulse animation on the green dot
- Compact state: "2 deliveries • 1 out for delivery" single row

#### Medications Card (Compact)

```
┌─────────────────────────────────────────────┐
│  💊 MEDICATIONS                              │
│─────────────────────────────────────────────│
│  ☐ Scar cream (alternate days)    ← tap    │
│  ☑ weekly-med 5mg (Friday)          done ✓   │
└─────────────────────────────────────────────┘
```

- Checklist style, each item tappable to mark as done
- Done items: green checkmark, slightly muted text
- Undone items: empty checkbox, full opacity
- Schedule note in parentheses (changes per week phase for scar cream)
- After all taken: card collapses to single row "All medications taken ✓"

#### Weather Card (Compact — single row)

```
┌─────────────────────────────────────────────┐
│  ☀️  18°C  Partly cloudy  │  🌧️ 10% rain   │
└─────────────────────────────────────────────┘
```

- Single-row compact card, no expansion needed
- Weather icon + temp + conditions + rain probability
- Shown in morning, auto-hides by evening unless rain expected

#### Important Emails Card

```
┌─────────────────────────────────────────────┐
│  ✉️ IMPORTANT EMAILS                3 unread │
│─────────────────────────────────────────────│
│                                             │
│  📌 AIMA — "Appointment confirmation"  2h   │
│  📌 Dr. Costa — "Follow-up results"   5h   │
│  📌 Bank — "Transfer notification"    1d   │
│                                             │
└─────────────────────────────────────────────┘
```

- Flagged/urgent only — not all unread
- Sender + subject truncated + age
- Pin icon for flagged, exclamation for urgent
- Tap → open Fastmail app (deep link)
- Compact state: "3 important emails" badge

### 2.5 Liveness Indicators

- **"Updated Xm ago"** timestamp on every card header — uses existing `DataFreshnessTracker`
- **Stale border:** Yellow border when data > 5 min old (already implemented)
- **Critical border:** Red pulsing border when data > 2 hours old
- **Active delivery pulse:** Green dot for "out for delivery" gently pulses (opacity 0.5 → 1.0, 2s cycle)
- **Calorie ring animation:** Fills smoothly when new meal data arrives (withAnimation spring)
- **Event countdown:** "in 45m" updates every minute via timer

### 2.6 Dark Mode Specifics

The app is already dark-themed. Key considerations:
- Card backgrounds: `PerchTheme.cardBackground` (already dark gray)
- Progress bars: Use vibrant fills on dark tracks (not the reverse)
- Status colors on dark: Green (#4CAF50), Yellow (#FFC107), Red (#F44336) — all need good contrast on dark cards
- Delivery progress track: `PerchTheme.border` (dark gray line), filled portion uses accent color
- Avoid pure white text for secondary info — use `textSecondary` and `textTertiary` for hierarchy

---

## Part 3: VP Engineering — Technical Architecture

### 3.1 Current Data Flow Analysis

**How data gets to the app today:**

```
Agent (BioChecha/Claudinho/Entregas)
    → dashboard-sync CLI (`node cli.js push`)
        → Supabase `dashboard_records` table INSERT/UPDATE
            → Supabase Realtime (postgres_changes)
                → ThePerch app (DashboardViewModel.subscribeToRecords)
                    → loadDashboard() → HomeViewModel.loadRecords()
                        → DailyBriefCard renders
```

**Key observations:**
1. `HomeViewModel.loadRecords()` fetches ALL records (limit 50), no category filter
2. `DailyBriefCard` extracts data in-view from the flat `records` array using `filter + compactMap`
3. Smart ordering in `HomeViewModel` already has time-of-day awareness (morning/midday/evening/night)
4. Realtime is functional — `DashboardViewModel` subscribes to `dashboard_records` changes
5. The 30-second cache prevents excessive API calls but means data can be 30s stale

### 3.2 Per-Card Data Mapping

#### Health Summary Card
- **Table:** `dashboard_records`
- **Filter:** `category = 'health'`, `type = 'measurement'`
- **Metrics used:** `sleep_duration`, `deep_sleep`, `avg_sleep_hrv`, `lowest_sleep_hr`, `readiness_score`, `sleep_score`, `activity_score`, `active_calories`, `steps`
- **Model:** `MeasurementData` (existing) — uses `metric`, `value`, `unit`, `timestamp`
- **Changes needed:** None — data already exists. Just need a new `HealthSummaryHomeCard` view that assembles these metrics into the hero layout.

#### Nutrition/Macros Card
- **Table:** `dashboard_records`
- **Filter:** `display_hint = 'progress_gauge'` (calories), `display_hint = 'macros_bar'` (macros)
- **Date filter:** `MeasurementData.context == todayString` for calories, `MacrosData.date == todayString` for macros
- **Models:** `MeasurementData` (calories — has value + target) and `MacrosData` (protein/carbs/fat + targets)
- **Changes needed:** None — `CaloriesCard` and `MacrosCard` already exist. Need a new composite `NutritionHomeCard` that combines both into the circular ring + bars layout.

#### Calendar — Today & Tomorrow
- **Table:** `dashboard_records`
- **Filter:** `category = 'calendar'`, `type = 'event'`
- **Model:** `EventData` — has `title`, `start` (Date), `end` (Date), `location`, `agentNotes`
- **Date filter:** `Calendar.current.isDateInToday(event.start)` / `isDateInTomorrow(event.start)`
- **Changes needed:** See bug analysis below (§3.3)

#### Active Deliveries
- **Table:** `dashboard_records`
- **Filter:** `category = 'deliveries'`, `type = 'delivery'`
- **Model:** `DeliveryData` — has `orderId`, `carrier`, `trackingNumber`, `status`, `eta`, `items[]`, `trackingUrl`
- **Status filter:** Exclude `delivered` and `cancelled`
- **Changes needed:** None data-side. Need a new `DeliveryHomeCard` that shows the mini progress tracker per delivery.

#### Medications Card (NEW)
- **Needs new data push.** Options:
  - **Option A (recommended):** Push as `type = 'checklist'`, `category = 'health'`, `title = 'Medications'`, data = `ChecklistData` with items
  - **Option B:** New record type `medication` — overkill for 2 items
- **Agent work:** Claudinho pushes a medications checklist record each morning as part of briefing sync
- **Interaction:** App needs a Supabase UPDATE to toggle `done` state on checklist items. Currently `ChecklistCard` exists but is read-only. Need to add mutation.
- **Schedule awareness:** Claudinho must calculate which medications apply today (scar cream schedule phase, weekly meds = Fridays)

#### Weather Card (NEW)
- **Needs new data push.** Push as `type = 'measurement'`, `category = 'health'` (or new category), with:
  ```json
  {
    "metric": "weather",
    "value": 18,
    "unit": "°C",
    "context": "2026-03-08",
    "display_value": "Partly cloudy, 10% rain"
  }
  ```
- **Or:** New record type. Simpler: use `text_note` with structured JSON.
- **Agent work:** Claudinho pushes weather data during morning briefing sync.

#### Important Emails Card (NEW)
- **Needs new data push.** Push as `type = 'text_note'`, `category = 'admin'`, with structured data:
  ```json
  {
    "body": "3 important emails",
    "tags": ["email", "urgent"],
    "emails": [
      {"sender": "AIMA", "subject": "Appointment confirmation", "age": "2h", "flagged": true},
      {"sender": "Dr. Costa", "subject": "Follow-up results", "age": "5h", "flagged": true}
    ]
  }
  ```
- **Agent work:** Claudinho pushes email summary during heartbeat checks (2-4x daily via fmail unread + fmail flagged)
- **App changes:** New `EmailSummaryCard` view; extend `TextNoteData` or create `EmailSummaryData` payload
- **Consideration:** Email data is sensitive. Supabase has RLS (row-level security). Ensure user_id filtering is enforced.

### 3.3 Calendar Bug Analysis: "No Events Tomorrow"

**Symptom:** Tomorrow card always shows "No events scheduled" even when events exist in the calendar.

**Root cause investigation:**

1. **How calendar events enter Supabase:**
   - Claudinho pushes them via `dashboard-sync CLI` as `type = 'event'`, `category = 'calendar'`
   - The `EventData` model has `start: Date` and `end: Date` fields decoded via ISO8601

2. **The `EventData` model looks correct:**
   ```swift
   struct EventData: Codable {
       let title: String
       let start: Date    // ISO8601 decoded
       let end: Date      // ISO8601 decoded
       let location: String?
       let agentNotes: String?
   }
   ```

3. **The filtering in `DailyBriefCard.tomorrowPreview`:**
   ```swift
   private var tomorrowPreview: CalendarSummaryData? {
       let tomorrowEvents = records.compactMap { record -> EventData? in
           guard let event = record.asEvent(),
                 Calendar.current.isDateInTomorrow(event.start) else { return nil }
           return event
       }.sorted { $0.start < $1.start }
       ...
   }
   ```

4. **The bug is almost certainly in the data push, not the app code.** The filtering logic is correct — `Calendar.current.isDateInTomorrow(event.start)` will match any event whose `start` falls within tomorrow's date boundaries in the device's timezone.

**Most likely causes (in order of probability):**

**(A) Tomorrow's events are never pushed to Supabase.** The morning briefing reads from Apple Calendar via `icalBuddy` and sends the briefing to Telegram, but there may be no corresponding `dashboard-sync push` for tomorrow's events. The dashboard-sync push might only push today's events.

**To verify:** Query Supabase for calendar events:
```bash
node ~/.openclaw/skills/dashboard-sync/cli.js query \
  --user_id 00000000-0000-0000-0000-000000000000 \
  --category calendar --type event --limit 20
```
Check if any records have `start` dates in the future/tomorrow.

**(B) Timezone mismatch.** If the agent pushes event times in UTC but the events are meant for Lisbon time (GMT+0 currently, but GMT+1 in summer), `isDateInTomorrow` could fail at edge hours. However, since Lisbon is currently GMT+0, this is less likely right now but will become an issue when clocks change.

**(C) The `fetchRecords` limit.** `HomeViewModel` fetches with `limit: 50`. If there are many health + delivery records, tomorrow's calendar events might be pushed out of the result set. The query is ordered by `created_at DESC`, so older calendar events (pushed in the morning for tomorrow) could be beyond the limit.

**Recommended fix:**
1. **Verify the agent push:** Ensure Claudinho pushes BOTH today's AND tomorrow's events to Supabase every morning (and re-pushes when calendar changes are detected).
2. **Increase limit or use targeted queries:** For the home screen, fetch calendar events separately with `category = 'calendar'` to ensure they're not crowded out.
3. **Add a `record_date` or `effective_date` column:** Currently the only dates are `created_at` and the `start` field buried inside JSON `data`. A top-level `effective_date` column would allow server-side filtering (e.g., "give me all events for tomorrow") without fetching everything.

### 3.4 Real-Time Update Strategy

**Current:** Supabase Realtime via `DashboardViewModel.setupRealtimeSubscriptions()`. On any INSERT/UPDATE/DELETE to `dashboard_records`, it calls `loadDashboard()` which re-fetches everything.

**Problem:** Re-fetching ALL records on every change is wasteful. If BioChecha pushes a meal update, we don't need to re-fetch deliveries.

**Proposed strategy:**

1. **Keep the global realtime subscription** (it's simple and works).
2. **On realtime event, only invalidate the affected category's cache:**
   ```swift
   // In the realtime handler:
   if let record = change.record {
       let categoryKey = record.category.rawValue
       supabaseService.invalidateCategoryCache(categoryKey)
       // Only refresh the affected view model
   }
   ```
3. **Per-card refresh:** Each card view model can independently refresh its data. Health card watches for `category = 'health'` changes only.
4. **Timer-based countdown updates:** Calendar card needs a 1-minute timer to update "in Xm" labels. This is local-only, no network call:
   ```swift
   .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
       // Force view update for relative time strings
   }
   ```

### 3.5 Architecture: From Monolithic to Modular

**Current problem:** `HomeViewModel` does everything — loads records, computes smart order, manages calories, events, deliveries, widgets, live activities. It's 250+ lines with two copies of `smartOrderedRecords` (one stored, one computed — there's actually a compile error here since both exist).

**Proposed architecture:**

```
HomeView
├── HealthSummaryHomeCard     ← own data extraction from records
├── NutritionHomeCard         ← combines CaloriesCard + MacrosCard
├── CalendarTodayCard         ← filters today's events
├── CalendarTomorrowCard      ← filters tomorrow's events
├── DeliveryHomeCard          ← active deliveries with progress
├── MedicationsCard           ← checklist with toggle
├── WeatherCompactCard        ← single-row weather
├── EmailSummaryCard          ← flagged emails
└── BodyCompositionCard       ← latest weigh-in (conditional)
```

Each card is a self-contained `View` that receives `[Record]` and extracts what it needs. The parent `HomeView` still fetches all records once and passes them down. Cards handle their own empty states.

**New `HomeViewModel` responsibilities:**
1. Fetch records (unchanged)
2. Determine card ordering based on time of day
3. Determine card visibility (hide weather in evening, etc.)
4. Pass records to each card

**Remove from HomeViewModel:**
- All the data extraction (`caloriesPercentText`, `nextEventTimeText`, `activeDeliveryCount`) — move to individual cards or a thin helper
- The duplicated `smartOrderedRecords` (currently both a `var` property and a computed property — this is a bug)

### 3.6 Performance Considerations

1. **Record limit:** Keep `limit: 50` for the main fetch but add a secondary fetch for calendar events if needed: `fetchRecords(category: .calendar, limit: 20)`. This ensures events aren't crowded out.
2. **Decoding cache:** `DecodingCache` already prevents re-decoding records on each render. No changes needed.
3. **View diffing:** Using `LazyVStack` (already in place) means off-screen cards aren't rendered.
4. **Realtime debounce:** If BioChecha pushes 4 records (calories + macros + weight + bf%), the realtime handler fires 4 times. Add a 500ms debounce:
   ```swift
   private var refreshDebounceTask: Task<Void, Never>?
   
   func scheduleRefresh() {
       refreshDebounceTask?.cancel()
       refreshDebounceTask = Task {
           try? await Task.sleep(nanoseconds: 500_000_000)
           guard !Task.isCancelled else { return }
           await loadRecords(forceRefresh: true)
       }
   }
   ```
5. **Offline support:** Already implemented via `CacheService`. Each card should gracefully show cached data with a stale indicator.

### 3.7 New Data Types Needed

| What | Record Type | Category | Display Hint | Pushed By | New? |
|------|-------------|----------|-------------|-----------|------|
| Medications checklist | checklist | health | checklist | Claudinho | **Yes** — new daily push |
| Weather | measurement | health | single_value | Claudinho | **Yes** — new daily push |
| Email summary | text_note | admin | status_list | Claudinho | **Yes** — new periodic push |
| Calendar (tomorrow) | event | calendar | timeline | Claudinho | **Existing type** — just needs to be pushed |

### 3.8 `smartOrderedRecords` Bug

There's a subtle issue in `HomeViewModel.swift`: both a stored property `var smartOrderedRecords: [Record] = []` (line 8) and a computed property `var smartOrderedRecords: [Record]` (line ~60) exist. The stored property shadows the computed one. This means `recomputeSmartOrder()` sets the stored `smartOrderedRecords`, but the actual ordering logic in the computed property may never execute (or vice versa depending on Swift resolution). **This should be fixed as part of Sprint 1.**

---

## Part 4: Execution Plan

### Sprint 1: Foundation & Bug Fixes (1 week)

**Goal:** Fix existing bugs, restructure HomeView for modular cards, no new data yet.

| Task | Estimate | Owner |
|------|----------|-------|
| Fix `smartOrderedRecords` dual-property bug | 1h | iOS |
| Verify calendar data push — query Supabase for tomorrow's events | 1h | Backend/Agent |
| Fix Claudinho to push tomorrow's calendar events to Supabase | 2h | Agent |
| Increase record fetch limit or add per-category fetches | 2h | iOS |
| Extract `HealthSummaryHomeCard` from DailyBriefCard | 3h | iOS |
| Extract `CalendarTodayCard` and `CalendarTomorrowCard` | 3h | iOS |
| Extract `NutritionHomeCard` (combines existing CaloriesCard + MacrosCard) | 2h | iOS |
| Refactor `DeliveryCard` into `DeliveryHomeCard` with progress tracker | 3h | iOS |
| Implement time-of-day card ordering in HomeView | 2h | iOS |
| Remove DailyBriefCard, replace with card stack | 2h | iOS |
| Add realtime refresh debounce (500ms) | 1h | iOS |
| QA: verify all existing data renders correctly in new layout | 2h | QA |

**Sprint 1 total: ~24h of work**

**Deliverable:** Home screen shows the same data as today but in modular cards with time-of-day ordering. Calendar bug fixed. No new data types.

### Sprint 2: New Data — Medications, Weather, Emails (1 week)

**Goal:** Add new data pushes from Claudinho, new card views in app.

| Task | Estimate | Owner |
|------|----------|-------|
| Claudinho: Push medications checklist to Supabase each morning | 3h | Agent |
| Claudinho: Push weather data to Supabase each morning | 2h | Agent |
| Claudinho: Push email summary during heartbeat (2-4x/day) | 3h | Agent |
| iOS: `MedicationsCard` with interactive checkboxes | 4h | iOS |
| iOS: Supabase mutation for checklist item toggle | 2h | iOS |
| iOS: `WeatherCompactCard` (single row) | 1h | iOS |
| iOS: `EmailSummaryCard` with flagged email list | 3h | iOS |
| iOS: `EmailSummaryData` model (extend DataPayloads.swift) | 1h | iOS |
| iOS: Deep link to Fastmail from email card | 1h | iOS |
| QA: end-to-end test — Claudinho pushes → app displays | 2h | QA |

**Sprint 2 total: ~22h of work**

**Deliverable:** Three new card types live. Medications are interactive. Weather shows in morning. Email summary refreshes through the day.

### Sprint 3: Polish — Animations, Liveness, Transitions (1 week)

**Goal:** Make it feel alive. Visual polish, micro-interactions, ambient transitions.

| Task | Estimate | Owner |
|------|----------|-------|
| Time-of-day ambient color tinting (header, accents) | 3h | iOS |
| Calorie ring animation (smooth fill on data update) | 2h | iOS |
| Delivery "out for delivery" pulse animation | 1h | iOS |
| Calendar event countdown timer (updates "in Xm" every minute) | 2h | iOS |
| Card expand/collapse transitions (compact ↔ full) | 4h | iOS |
| Hero card designation (larger card for primary module) | 2h | iOS |
| Stale data indicator refinement (graduated borders) | 1h | iOS |
| Empty state illustrations for each card | 3h | Design |
| Haptic feedback on card interactions | 1h | iOS |
| Performance profiling — ensure <16ms frame time | 2h | iOS |
| QA: full visual review across time periods | 2h | QA |

**Sprint 3 total: ~23h of work**

**Deliverable:** Polished, production-ready home screen with animations and liveness indicators.

### Sprint 4: Body Composition Card + Widget Updates (1 week, optional)

**Goal:** Add body composition card, update iOS widgets to match new home layout.

| Task | Estimate | Owner |
|------|----------|-------|
| iOS: `BodyCompositionHomeCard` (conditional on weigh-in day) | 3h | iOS |
| iOS: Update widget data sync for new card types | 4h | iOS |
| iOS: Lock screen widgets for calories + next event | 4h | iOS |
| Agent: Claudinho re-pushes calendar events when changes detected (not just morning) | 3h | Agent |
| Agent: BioChecha pushes body comp data on weigh-in | 1h (verify existing) | Agent |
| Performance: Add per-category Supabase queries for large record counts | 3h | iOS |
| QA: regression test all cards + widgets | 3h | QA |

**Sprint 4 total: ~21h of work**

### Risks & Dependencies

| Risk | Impact | Mitigation |
|------|--------|------------|
| Calendar bug is in agent push, not app | Blocks Sprint 1 | Query Supabase first to confirm; fix agent promptly |
| Email data sensitivity in Supabase | Security concern | Ensure RLS policies are correct; only push subjects/senders, never body content |
| BioChecha push frequency | Nutrition card feels stale | Verify BioChecha pushes after every `meal_tracker.py` log; add retry |
| Realtime subscription drops | Cards show stale data | `RealtimeReconnectManager` already handles this; verify it works |
| Supabase record count growth | Slower queries over time | Add `expires_at` to calendar events (auto-cleanup); index on `category` + `created_at` |
| `smartOrderedRecords` dual-property | Runtime confusion | Fix immediately in Sprint 1 before any other work |

### Dependencies Map

```
Sprint 1 (Foundation)
    ↓
Sprint 2 (New Data) — depends on agent work running in parallel
    ↓
Sprint 3 (Polish) — no blockers, purely iOS
    ↓
Sprint 4 (Widgets) — optional, can ship after Sprint 3
```

**Agent work (Claudinho changes) can start immediately and run in parallel with Sprint 1 iOS work.**

---

## Appendix: Quick Glance Bar Evolution

The current Quick Glance bar (calories %, next event, delivery count) should remain but evolve:

- Move it **above** the card stack (just below the header) as a persistent summary strip
- Add weather icon + temp as a 4th item
- Make each item tappable — scrolls to the relevant card
- Items adapt: show medication status ("💊 1/2") when medications are pending

---

*This document was produced as a collaborative brainstorm between VP Product, VP Design, and VP Engineering perspectives. It should be reviewed by Fábio before execution begins.*

---

## Addendum: Remote Admin Controls (Sprint 4 scope)

### Problem
When the gateway goes down or needs attention, Fábio currently has no way to fix it remotely from his phone. The Admin section shows "Offline" but offers no remediation.

### Solution
Add remote admin action buttons to the Admin section that trigger commands on the Mini via a Supabase command queue.

### Architecture
1. **Command Queue Table** — New `admin_commands` table in Supabase:
   - `id`, `user_id`, `command` (enum: restart_gateway, doctor_fix, status_check), `status` (pending/executing/completed/failed), `result` (JSON), `created_at`, `executed_at`
   - RLS: only authenticated user can insert/read their own commands

2. **Mini-side Poller** — A lightweight daemon/cron on the Mini that:
   - Polls `admin_commands` every 30s for pending commands
   - Executes the allowed command (strict allowlist)
   - Updates status + result in Supabase
   - Pushes fresh gateway status record after execution

3. **iOS App** — Admin section gets:
   - "Restart Gateway" button (confirmation dialog first)
   - "Run Doctor Fix" button (confirmation dialog first)
   - Status indicator: shows command progress (pending → executing → result)
   - Command history (last 5 commands with timestamps + results)

### Security
- Strict command allowlist (only restart_gateway, doctor_fix, status_check)
- User auth required (Supabase RLS)
- Rate limiting (max 1 command per 2 minutes)
- Confirmation dialog before any action
- Audit log of all commands executed

### Design (to be refined by VP Design)
- Buttons in Admin section, below the gateway status card
- Use destructive/danger styling for restart (red-tinted)
- Use primary styling for doctor fix (blue)
- Show execution status inline with spinner → checkmark/error
