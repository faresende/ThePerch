# ThePerch Performance Audit

**Date:** 2026-03-08
**Auditor:** Performance Engineering Subagent
**Codebase:** `/ios/ThePerch/Sources/ThePerch/` (67 Swift files)

---

## 1. Executive Summary

### Top 3 Root Causes of Slowness

1. **Every section view fires its own independent `fetchRecords()` on `.task{}` — creating a waterfall of redundant network requests.** HomeView fetches ALL records (limit 50), then when you swipe to Health, it fetches health records. Swipe to Deliveries, another fetch. Swipe to Calendar, another. Swipe to Admin, *three* parallel fetches. Each section creates its own ViewModel with its own Supabase call. The 30-second cache helps on re-renders but NOT on first visit to each section. This is the primary cause of both slow initial load AND first-swipe hang.

2. **Data is decoded from JSON repeatedly across views via `record.asDelivery()`, `record.asEvent()`, etc. in computed properties that re-execute on every SwiftUI render cycle.** The `DecodingCache` mitigates per-record cost, but `smartOrderedRecords` (HomeViewModel) calls `.asDelivery()`, `.asEvent()`, `.asMeasurement()` etc. on ALL 50 records every time the computed property is accessed — and it's accessed on every body evaluation. DailyBriefCard does the same. CalendarView's `todayEvents`/`upcomingEvents` computed properties also decode every record every render.

3. **All section views are instantiated eagerly inside a `TabView(.page)` ForEach**, meaning every section's SwiftUI body is evaluated even before the user swipes to it. Combined with each section triggering `.task { await viewModel.loadRecords() }`, this means ALL sections begin loading data simultaneously on first appear.

---

## 2. Findings

### Phase 1: Data Flow Analysis

#### F1.1 — Double fetch on app launch (CRITICAL)

**What's happening:**
- `ThePerchApp.swift:24-26` — `.task` on MainTabView calls `dashboardViewModel.setupRealtimeSubscriptions()`
- `MainTabView.swift:72-74` — `.task` calls `dashboardViewModel.loadDashboard()`
- `DashboardViewModel.swift:42-64` — `loadDashboard()` fetches sections + home_widgets in parallel
- Then immediately, the TabView renders all section views:
  - HomeView `.task` → `HomeViewModel.loadRecords()` → `fetchRecords(limit: 50)` (ALL records)
  - HealthView `.task` → `HealthViewModel.loadRecords()` → `fetchRecords(category: .health, limit: 100)`
  - DeliveriesView `.task` → `SectionViewModel.loadRecords()` → `fetchRecords(category: .deliveries, limit: 100)`
  - CalendarView `.task` → `SectionViewModel.loadRecords()` → `fetchRecords(category: .calendar, limit: 100)`
  - AdminView `.task` → `AdminViewModel.loadRecords()` → `fetchAgents()` + `fetchRecords(category: .admin, type: .costSummary)` + `fetchRecords(category: .admin)`
  - BookmarksView `.task` → `SectionViewModel.loadRecords()` → `fetchRecords(category: .bookmarks, limit: 100)`

**Total network requests on launch:** ~9 Supabase queries fire nearly simultaneously.

**Why it's slow:** Even with connection reuse, 9 HTTP requests in parallel saturate the network pipe, compete for CPU time for JSON decoding, and trigger a storm of @Observable updates that cause SwiftUI to re-evaluate bodies.

- **Severity:** Critical
- **Estimated impact if fixed:** 60-70% reduction in initial load time

#### F1.2 — HomeView fetches ALL records unfiltered (HIGH)

**What's happening:**
- `HomeViewModel.swift:41` — `fetchRecords(limit: 50)` with NO category filter
- This returns up to 50 records across ALL categories
- The `smartOrderedRecords` computed property then filters/sorts these manually on the client

**Why it's slow:** Fetching 50 records with no filter means a larger payload, more JSON to decode, and the query itself is slower (no index hit on category).

- **Severity:** High
- **Estimated impact if fixed:** 15-20% faster HomeView load

#### F1.3 — Realtime subscription setup is async but blocks UI perception (MEDIUM)

**What's happening:**
- `ThePerchApp.swift:25` — `await dashboardViewModel.setupRealtimeSubscriptions()` runs in the `.task`
- `DashboardViewModel.swift:107-137` — `setupRealtimeSubscriptions()` calls `subscribeToRecords` + `subscribeToAgents`
- `SupabaseService.swift:341-344` — creates channel, subscribes with `await channel.subscribe()`

**Why it's slow:** The `await channel.subscribe()` call blocks until the WebSocket connection is established. If the network is slow, this delays the entire `.task` block. While it doesn't directly block `loadDashboard()` (they're in separate `.task` blocks), the realtime subscription setup is ordered before the crash report check.

- **Severity:** Medium
- **Estimated impact if fixed:** Minor improvement to perceived launch time

#### F1.4 — No data preloading or prefetch strategy (HIGH)

**What's happening:** There is zero prefetching. Each section loads on-demand when its view appears. The cache has a 30-second TTL (`CacheEntry.isStale`), so data expires quickly.

**Why it's slow:** First swipe to any section = cold load = network request + decode + render. This is the direct cause of the "first swipe hang."

- **Severity:** High
- **Estimated impact if fixed:** Eliminates first-swipe hang entirely

#### F1.5 — `DecodingCache.shared.clear()` on every fetch (MEDIUM)

**What's happening:**
- `SupabaseService.swift:173` — `fetchRecords()` calls `DecodingCache.shared.clear()` at the start
- This nukes the entire NSCache of decoded payloads
- Every subsequent `record.asMeasurement()`, `.asDelivery()` etc. must re-decode from scratch

**Why it's slow:** With 9 fetches firing at launch, the decoding cache is cleared 9 times, rendering it useless during the initial load. Subsequent renders re-decode everything.

- **Severity:** Medium
- **Estimated impact if fixed:** 10-15% reduction in CPU work during initial load

---

### Phase 2: View Rendering Analysis

#### F2.1 — TabView(.page) creates ALL section bodies eagerly (CRITICAL)

**What's happening:**
- `MainTabView.swift:61-67` — `TabView` with `.tabViewStyle(.page)` contains a `ForEach` over ALL visible sections
- SwiftUI's `.page` tab view style pre-renders adjacent pages for smooth swiping
- Each section view creates its own `@State private var viewModel`, which triggers `.task`

```swift
TabView(selection: $selectedIndex) {
    ForEach(Array(visibleSections.enumerated()), id: \.offset) { index, section in
        SectionView(section: section)  // ALL created at once
            .tag(index)
    }
}
.tabViewStyle(.page(indexDisplayMode: .never))
```

**Why it's slow:** A paged TabView pre-creates the current page + neighbors. With 6 sections, SwiftUI evaluates at minimum 2-3 section bodies on launch. Each triggers a `.task` with network fetch. On first swipe, the destination view was already created but its data load may still be in-flight or just completed.

- **Severity:** Critical
- **Estimated impact if fixed:** Directly eliminates first-swipe hang

#### F2.2 — `smartOrderedRecords` is a massive computed property (HIGH)

**What's happening:**
- `HomeViewModel.swift:71-165` — `smartOrderedRecords` is a computed property that:
  1. Calls `.asDelivery()` on potentially ALL 50 records multiple times (lines 82, 130, 145)
  2. Calls `.asEvent()` on ALL records multiple times (lines 88, 99, 107, 114, 125, 132, 152)
  3. Calls `.asMeasurement()` on ALL records multiple times (lines 95, 138, 142)
  4. Performs multiple sorts
  5. Uses a `Set<UUID>` for dedup
- This is called every time HomeView's body is evaluated

**Why it's slow:** Each call to `.asDelivery()` etc. hits the DecodingCache, but the repeated iterations over all records with multiple decode attempts per record adds significant CPU overhead in the view body.

- **Severity:** High
- **Estimated impact if fixed:** 20-30% faster HomeView renders

#### F2.3 — `DailyBriefCard` re-processes all records on every render (HIGH)

**What's happening:**
- `DailyBriefCard.swift` — accepts `records: [Record]` array and computes:
  - `sleepSummary` (lines ~200-230): filters + maps + sorts health records, decodes measurements
  - `calendarSummary` (lines ~240-255): compactMaps + sorts events
  - `deliverySummary` (lines ~260-280): compactMaps + filters deliveries
  - `nutritionSummary(forYesterday:)` (lines ~285-340): filters + sorts calories/macros records
- ALL of these are computed properties evaluated during body rendering

**Why it's slow:** Same records are decoded and filtered 4+ times in a single render pass. Combined with `smartOrderedRecords`, a single HomeView render decodes the same JSON data 8-12 times.

- **Severity:** High
- **Estimated impact if fixed:** 15-20% faster HomeView renders

#### F2.4 — DateFormatter created in HomeView body (LOW)

**What's happening:**
- `HomeView.swift:187-190` — `shortDateString` computed property creates a new `DateFormatter()` each time:
```swift
private var shortDateString: String {
    let f = DateFormatter()
    f.dateFormat = "EEE MMM d"
    return f.string(from: Date.now)
}
```

**Why it's slow:** DateFormatter allocation is surprisingly expensive (~50μs). While minor on its own, this runs on every body evaluation.

- **Severity:** Low
- **Estimated impact if fixed:** Negligible in isolation, good hygiene

#### F2.5 — Section views re-run appear/disappear animations on swipe (LOW)

**What's happening:**
- `MainTabView.swift:127-133` — SectionView uses `appeared` state with opacity/offset animation
- `onAppear { appeared = true }` / `onDisappear { appeared = false }` means every swipe triggers the enter animation

**Why it's slow:** The opacity 0→1 and offset 12→0 animation triggers a render pass with interpolation. It's a minor cost but adds to the perception of sluggishness.

- **Severity:** Low
- **Estimated impact if fixed:** Slightly smoother swipe feel

#### F2.6 — `visibleSections` computed on every render (LOW)

**What's happening:**
- `MainTabView.swift:13-15` — `visibleSections` filters + sorts sections on every body eval:
```swift
var visibleSections: [Section] {
    dashboardViewModel.sections.filter { $0.isVisible && $0.slug != "legal" }.sorted { ... }
}
```

**Why it's slow:** This runs on every render cycle. With 6-7 sections it's fast, but the sort allocates a new array each time.

- **Severity:** Low
- **Estimated impact if fixed:** Negligible

---

### Phase 3: JSON/Decoding Analysis

#### F3.1 — `decodeData<T>()` performs JSONEncoder → JSONDecoder round-trip (MEDIUM)

**What's happening:**
- `Record.swift:120-127` — `decodeData<T>()` encodes `JSONValue` → `Data` → decodes to `T`:
```swift
func decodeData<T: Decodable>(as type: T.Type) -> T? {
    if let cached: T = DecodingCache.shared.get(id, as: type) { return cached }
    guard let jsonData = try? Self.jsonEncoder.encode(data),
          let decoded = try? Self.jsonDecoder.decode(T.self, from: jsonData) else { return nil }
    DecodingCache.shared.set(decoded, for: id, as: type)
    return decoded
}
```

**Why it's slow:** This is an encode-then-decode pattern. The `data` field is already a parsed `JSONValue` enum, but instead of walking the enum directly, we serialize it back to JSON bytes then parse those bytes again. For 50 records decoded 3-4 times each (across views), this is significant overhead.

- **Severity:** Medium
- **Estimated impact if fixed:** 15-20% less CPU during rendering

#### F3.2 — DecodingCache keyed by record ID + type name, but cleared too aggressively (MEDIUM)

**What's happening:**
- `Record.swift:91-112` — DecodingCache uses NSCache with 500 entry limit
- `SupabaseService.swift:173` — `DecodingCache.shared.clear()` is called at the START of every `fetchRecords()` call
- With 9 fetches on launch, the cache is cleared 9 times before any view can benefit from it

**Why it's slow:** The cache is useless during the most critical period (initial load). Only helps during subsequent renders if no refresh is triggered.

- **Severity:** Medium
- **Estimated impact if fixed:** Significant during initial load; makes DecodingCache actually work

---

### Phase 4: Network Analysis

#### F4.1 — 9+ Supabase requests on app launch (CRITICAL)

**What's happening:** (Detailed in F1.1)
1. `fetchSections()` — GET /sections
2. `fetchHomeWidgets()` — GET /home_widgets
3. `fetchRecords(limit: 50)` — GET /dashboard_records (HomeView)
4. `fetchRecords(category: health)` — GET /dashboard_records?category=health
5. `fetchRecords(category: deliveries)` — GET /dashboard_records?category=deliveries
6. `fetchRecords(category: calendar)` — GET /dashboard_records?category=calendar
7. `fetchRecords(category: admin, type: costSummary)` — GET /dashboard_records?category=admin&type=cost_summary
8. `fetchRecords(category: admin)` — GET /dashboard_records?category=admin
9. `fetchAgents()` — GET /agents
10. Plus: `subscribeToRecords` (WebSocket) + `subscribeToAgents` (WebSocket)

**Why it's slow:** TCP connection setup, TLS handshake, HTTP overhead × 9. Even with HTTP/2 multiplexing, each request has independent latency.

- **Severity:** Critical
- **Estimated impact if fixed:** 50-60% faster initial load

#### F4.2 — HomeView's unfiltered fetch duplicates data from section fetches (HIGH)

**What's happening:**
- HomeView: `fetchRecords(limit: 50)` — gets 50 records across all categories
- HealthView: `fetchRecords(category: .health, limit: 100)` — gets same health records again
- DeliveriesView: `fetchRecords(category: .deliveries, limit: 100)` — gets same delivery records again
- etc.

The 30-second cache key is based on `category_type_limit`, so `all_all_50` ≠ `health_all_100` — no cache hit between them.

**Why it's slow:** 50% of the data is fetched twice. The HomeView fetch alone could serve all sections if records were shared from a single source.

- **Severity:** High
- **Estimated impact if fixed:** Could eliminate 4-5 network requests entirely

#### F4.3 — AdminView fires 3 parallel fetches (MEDIUM)

**What's happening:**
- `AdminViewModel.swift:80-90` — fires `fetchAgents()`, `fetchRecords(category: admin, type: costSummary)`, and `fetchRecords(category: admin)` in parallel

**Why it's slow:** 3 requests for one section. The admin records fetch (limit 50) includes cost summary records, so the type-filtered fetch is redundant data.

- **Severity:** Medium
- **Estimated impact if fixed:** 1-2 fewer requests

#### F4.4 — Realtime change triggers full dashboard reload (MEDIUM)

**What's happening:**
- `DashboardViewModel.swift:119-127` — every realtime INSERT/UPDATE/DELETE on `dashboard_records` triggers `await self.loadDashboard()` which refetches sections + widgets
- `DashboardViewModel.swift:132-136` — every realtime agent change also triggers full `loadDashboard()`

**Why it's slow:** A single record change causes full sections + widgets refetch, even though the change was just one record. This is wasteful and causes UI flicker.

- **Severity:** Medium
- **Estimated impact if fixed:** Reduces unnecessary refetches during active use

#### F4.5 — `onChange(of: selectedIndex)` triggers full dashboard reload for stale sections (MEDIUM)

**What's happening:**
- `MainTabView.swift:78-86` — when swiping to a section, if `DataFreshnessTracker.shared.isStale(key)`, it calls `dashboardViewModel.loadDashboard(forceRefresh: true)` — this refreshes ALL sections, not just the stale one.

**Why it's slow:** Swiping to section B triggers a refresh of A, B, C, D, E, F.

- **Severity:** Medium
- **Estimated impact if fixed:** Targeted refresh would be much lighter

---

### Phase 5: Image/Asset Analysis

#### F5.1 — No AsyncImage usage detected (OK)

No image loading from URLs was found in the codebase. All icons are SF Symbols. No performance concern here.

#### F5.2 — Bookmark images not loaded (OK)

`BookmarkData` has an `imageUrl` field but `BookmarkCard` was not found to load it asynchronously. No concern.

---

### Phase 6: Section Swipe Performance

#### F6.1 — First swipe hang caused by eager view creation + on-demand data load (CRITICAL)

**What's happening:** This is the combination of F2.1 + F1.4:
1. TabView creates all section views eagerly
2. Each section's `.task` fires `loadRecords()` immediately
3. On first swipe, the destination section's data may still be loading (network latency)
4. The view shows a skeleton/loading state, then snaps to content — perceived as a "hang"
5. Subsequent swipes are fast because the 30-second cache serves data instantly

**Why it's slow:** The user sees the section for 500-2000ms in loading state before content appears.

- **Severity:** Critical
- **Estimated impact if fixed:** Eliminates the first-swipe hang completely

#### F6.2 — Tab switch triggers haptic + stale check + potential full reload (LOW)

**What's happening:**
- `MainTabView.swift:76` — `PerchHaptics.selection()` fires on every tab change
- Lines 78-86 — staleness check may trigger full reload

**Why it's slow:** The haptic is fine, but the potential full reload on every swipe adds latency.

- **Severity:** Low
- **Estimated impact if fixed:** Minor

---

## 3. Recommended Fix Plan

### Quick Wins (< 1 hour each, high impact)

#### QW1: Stop clearing DecodingCache on fetch
**File:** `SupabaseService.swift:173`
**Change:** Remove `DecodingCache.shared.clear()` from `fetchRecords()`. Instead, clear only entries for records whose IDs are no longer in the new fetch result (or don't clear at all — the NSCache with 500-entry limit handles eviction).
**Impact:** DecodingCache actually works during initial load. ~10-15% less CPU.

#### QW2: Cache `smartOrderedRecords` and `DailyBriefCard` data
**Files:** `HomeViewModel.swift`, `DailyBriefCard.swift`
**Change:** Convert `smartOrderedRecords` from a computed property to a stored property that's recalculated only when `records` changes (in `loadRecords()`). For DailyBriefCard, pre-compute the summary data in HomeViewModel and pass structured data instead of raw records.
**Impact:** Eliminates redundant decoding during renders. ~20-30% faster HomeView body evaluation.

#### QW3: Move DateFormatter out of HomeView body
**File:** `HomeView.swift:187-190`
**Change:** Add a static formatter to `PerchFormatters`:
```swift
static let shortWeekdayDate: DateFormatter = { ... }()
```
**Impact:** Minor, but eliminates allocation on every render.

#### QW4: Only refresh the stale section, not all sections
**File:** `MainTabView.swift:78-86`
**Change:** Instead of `dashboardViewModel.loadDashboard(forceRefresh: true)`, call the specific section's `viewModel.refresh()`. This requires the section view to expose its refresh.
**Impact:** Targeted refresh = 1 request instead of 2-9.

### Medium Effort (1-4 hours, medium-high impact)

#### ME1: Single-fetch architecture — fetch ALL records once, distribute to sections
**Files:** `DashboardViewModel.swift`, `HomeViewModel.swift`, `HealthViewModel.swift`, `SectionViewModel.swift`, all section views
**Change:**
1. `DashboardViewModel.loadDashboard()` fetches ONE call: `fetchRecords(limit: 200)` (all records, all categories)
2. Store result in `DashboardViewModel.allRecords`
3. Each section view reads from `dashboardViewModel.allRecords.filter { $0.category == .health }` instead of making its own fetch
4. Remove per-section `loadRecords()` calls
5. Keep `fetchAgents()` as a separate call (different table)

**Impact:** Reduces 7-8 requests to 1-2. Eliminates first-swipe hang. **This is the single highest-impact change.**

#### ME2: Lazy section initialization
**Files:** `MainTabView.swift`, `SectionView`
**Change:** Use a custom paging approach or wrap section content in lazy containers. Ensure that section ViewModels and their `.task` blocks only fire when the section is actually swiped to (not pre-created). Consider using `LazyHStack` inside a `ScrollView` with `.scrollTargetBehavior(.paging)` (iOS 17+) instead of `TabView(.page)`.
**Impact:** Only the current section + immediate neighbors load data, not all 6.

#### ME3: Direct JSONValue → typed struct decoding (skip encode/decode round-trip)
**File:** `Record.swift:120-127`, new utility
**Change:** Write a `JSONValue` → `T` decoder that walks the enum tree directly instead of encoding to Data then decoding:
```swift
func decodeData<T: Decodable>(as type: T.Type) -> T? {
    if let cached = DecodingCache.shared.get(id, as: type) { return cached }
    let decoded = JSONValueDecoder.decode(type, from: data)
    if let decoded { DecodingCache.shared.set(decoded, for: id, as: type) }
    return decoded
}
```
**Impact:** ~2x faster per-decode operation. Eliminates the double-encode overhead.

#### ME4: Pre-decode records after fetch
**File:** `SupabaseService.swift` or `DashboardViewModel.swift`
**Change:** After fetching records, iterate once and call `record.decodeData(as: appropriateType)` to populate the DecodingCache. This front-loads decoding to a single pass rather than scattering it across multiple view renders.
**Impact:** Decoding happens once, predictably, rather than scattered across render cycles.

#### ME5: Smarter realtime handling — merge change into local state
**File:** `DashboardViewModel.swift:119-127`
**Change:** When a realtime INSERT arrives with a decoded `Record`, insert it into `allRecords` directly instead of refetching everything. For UPDATE, find and replace. For DELETE, remove by ID.
**Impact:** Eliminates full reload on every realtime change. Near-instant UI updates.

### Architecture Changes (4+ hours, transformative)

#### AC1: Introduce a RecordStore (single source of truth for all records)
**New file:** `RecordStore.swift`
**Change:** Create an `@Observable` RecordStore that:
1. Holds all records in a single `[Record]` array
2. Provides computed/cached filtered views: `healthRecords`, `deliveryRecords`, etc.
3. Is the ONLY thing that fetches from Supabase
4. All ViewModels observe the RecordStore instead of calling SupabaseService directly
5. Realtime changes update the store; views react automatically

**Impact:** Eliminates ALL redundant fetches. Single source of truth. Perfect cache invalidation. This is the proper architecture.

#### AC2: Offline-first with background sync
**Files:** `CacheService.swift`, `RecordStore.swift`
**Change:**
1. On launch, immediately load cached data from disk (CacheService)
2. Show cached data instantly (0ms perceived load)
3. Background fetch from Supabase
4. Diff and update only changed records
5. UI smoothly updates via @Observable

**Impact:** Near-instant app launch. Data always visible. Network latency hidden.

#### AC3: Server-side aggregation endpoint
**Change:** Create a single Supabase RPC or Edge Function that returns:
```json
{
  "sections": [...],
  "records": [...],
  "agents": [...],
  "widgets": [...]
}
```
One request, one response, everything the app needs.

**Impact:** 1 HTTP request instead of 9. Minimal latency. Can include server-side filtering/sorting.

---

## 4. Proposed Sprint Plan

### Sprint 1: "Stop the Bleeding" (1-2 days)

**Goal:** Eliminate the worst symptoms with minimal code change.

| Task | Est. | Ref |
|------|------|-----|
| Remove `DecodingCache.shared.clear()` from fetchRecords | 15 min | QW1 |
| Cache `smartOrderedRecords` as stored property | 30 min | QW2 |
| Pre-compute DailyBriefCard data in HomeViewModel | 45 min | QW2 |
| Fix DateFormatter in HomeView | 5 min | QW3 |
| Targeted stale-section refresh instead of full reload | 30 min | QW4 |
| **Single-fetch: DashboardVM fetches all records, sections read from it** | **3-4 hrs** | **ME1** |

**Expected outcome:** Initial load drops from ~3-5s to ~1-2s. First-swipe hang eliminated.

### Sprint 2: "Solid Foundation" (2-3 days)

**Goal:** Proper architecture for sustained performance.

| Task | Est. | Ref |
|------|------|-----|
| Build RecordStore as single source of truth | 4 hrs | AC1 |
| Migrate all ViewModels to read from RecordStore | 3 hrs | AC1 |
| Direct JSONValue→struct decoder (skip encode round-trip) | 2 hrs | ME3 |
| Pre-decode records after fetch | 1 hr | ME4 |
| Smart realtime: merge changes into RecordStore locally | 2 hrs | ME5 |
| Offline-first: show cached data on launch, background refresh | 3 hrs | AC2 |

**Expected outcome:** Sub-second app launch. Instant section switching. Smooth realtime updates. Works offline.

### Sprint 3: "Polish" (1-2 days)

**Goal:** Network optimization and edge cases.

| Task | Est. | Ref |
|------|------|-----|
| Lazy section views (replace TabView with ScrollView+paging) | 3 hrs | ME2 |
| Server-side aggregation endpoint (Supabase RPC) | 3 hrs | AC3 |
| Profile with Instruments and fix remaining hotspots | 2 hrs | — |
| Reduce AdminView from 3 fetches to 1 | 30 min | F4.3 |

**Expected outcome:** Single network request. Minimal memory footprint. Production-ready performance.

---

## Appendix: File Reference Quick Index

| File | Key Issue |
|------|-----------|
| `ThePerchApp.swift` | Launch sequence, dual .task blocks |
| `MainTabView.swift:61-67` | Eager TabView creates all sections |
| `MainTabView.swift:78-86` | Full reload on stale section swipe |
| `DashboardViewModel.swift:42-64` | loadDashboard: sections + widgets |
| `DashboardViewModel.swift:119-127` | Realtime triggers full reload |
| `HomeViewModel.swift:41` | Unfiltered fetchRecords(limit:50) |
| `HomeViewModel.swift:71-165` | smartOrderedRecords heavy compute |
| `HealthViewModel.swift:53-65` | Independent fetchRecords per section |
| `SectionViewModel.swift:43-58` | Independent fetchRecords per section |
| `AdminViewModel.swift:80-90` | 3 parallel fetches |
| `SupabaseService.swift:173` | DecodingCache.clear() on every fetch |
| `Record.swift:120-127` | Encode→Decode round-trip for typed data |
| `DailyBriefCard.swift:200-340` | Re-processes all records every render |
| `HomeView.swift:187-190` | DateFormatter in computed property |
| `CalendarView.swift:13-30` | Computed properties decode all records |
| `DeliveriesView.swift:14-28` | Computed properties decode all records |
| `BookmarksView.swift:11-37` | Computed properties decode all records |
