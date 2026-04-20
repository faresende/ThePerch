# Performance Review — ThePerch Navigation Choppiness

**Reviewer:** swe-vp (Staff Engineer / VP of Engineering)
**Date:** 2026-03-18
**Symptom:** App feels choppy when navigating between tabs

---

## Findings

### P0 — All views re-render on every `allRecords` write

**Location:** `DashboardViewModel.swift:9-38` + all section views

**Problem:**
`DashboardViewModel` is `@Observable`. Every write to `allRecords` (including realtime updates from Supabase) triggers a SwiftUI re-render in **every view that reads any property derived from `allRecords`** — that includes all 8 section views simultaneously, even the ones not on screen.

The filtered computed properties (`healthRecords`, `deliveryRecords`, etc.) are evaluated on every render cycle. With 500 records and 8 categories, this is 500 × 8 = 4,000 filter iterations every time any record changes.

**Recommended Fix:**
Pre-compute and cache the filtered arrays. Replace:
```swift
var healthRecords: [Record] { allRecords.filter { $0.category == .health } }
```
With:
```swift
private(set) var healthRecords: [Record] = []
private(set) var deliveryRecords: [Record] = []
// ...etc

// Called after allRecords changes:
private func rebuildFilteredArrays() {
    healthRecords = allRecords.filter { $0.category == .health }
    deliveryRecords = allRecords.filter { $0.category == .deliveries }
    // ...
}
```
This means views only re-render when their specific category array actually changes.

**Impact:** High. Eliminates the cross-tab render cascade.

---

### P0 — `TabView(.page)` renders all section views at startup

**Location:** `MainTabView.swift:56-62`

**Problem:**
`TabView` with `.tabViewStyle(.page)` in SwiftUI renders ALL child views eagerly at startup, not lazily. With 8+ sections, all 8 `SectionView` instances are created, their `onAppear` fires, and their view models load — even for tabs the user hasn't visited.

**Recommended Fix:**
Use `LazyView` wrapper to defer rendering until the tab is actually visited:
```swift
struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}

// In TabView:
ForEach(...) { index, section in
    LazyView(SectionView(section: section))
        .tag(index)
}
```

**Impact:** High. Reduces startup rendering from 8 views to 1.

---

### P1 — `.safeAreaPadding(.top, 64)` applied inside animation

**Location:** `MainTabView.swift:218`

**Problem:**
`.safeAreaPadding(.top, 64)` triggers layout recalculation. It's applied inside a `ZStack` and combined with `.animation(.spring, value: appeared)`. On every tab swipe, `appeared` flips false → true, triggering the spring animation AND the safe area layout recalculation simultaneously.

**Recommended Fix:**
Move `.safeAreaPadding` outside the animated view, or use a fixed `Spacer(minLength: 64)` at the top of each section's `ScrollView`. Layout passes should not be animated unless intentional.

**Impact:** Medium. Reduces jank on tab switch.

---

### P1 — `cardAppear` animations fire on every tab revisit

**Location:** All section views (e.g., `HealthView.swift:~35`)

**Problem:**
Each section view has `@State private var cardsAppeared = false` that triggers a cascade of `.cardAppear(index:)` staggered animations. `onDisappear` resets `appeared = false` in `SectionView`, which on re-visit re-triggers all card animations. Users see cards re-animating in on every tab switch.

**Recommended Fix:**
Only play card appear animations once. Use `@AppStorage` or persist the "has appeared" state so it doesn't reset:
```swift
@State private var cardsAppeared = false
// change onDisappear from resetting to not resetting:
// .onDisappear { appeared = false }  ← REMOVE THIS
```

**Impact:** Medium. Eliminates re-animation jank on tab revisit.

---

### P2 — 500 records fetched as one batch, all pre-decoded synchronously

**Location:** `DashboardViewModel.swift:76`, `SupabaseService.swift:360`

**Problem:**
`fetchRecords(limit: 500)` fetches all 500 records at once and immediately calls `preDecodeRecords()` which iterates all 500 synchronously on the main actor. The JSON decode loop is `nonisolated` but the cache writes are not. With workout sessions having complex nested exercise arrays, each decode is non-trivial.

**Recommended Fix:**
- Reduce limit to 200 for initial fetch, lazy-load older records on demand
- Or move `preDecodeRecords` to a background `Task` with actor-isolated updates

**Impact:** Low-medium. Mostly affects cold start, not navigation.

---

## Prioritized Fix List

| Priority | Fix | Effort | Impact |
|----------|-----|--------|--------|
| 1 | Cache filtered record arrays in DashboardViewModel | 30min | -60% re-renders |
| 2 | LazyView wrapper for TabView sections | 20min | -70% startup render |
| 3 | Remove onDisappear card animation reset | 5min | Smoother tab revisits |
| 4 | Move safeAreaPadding outside animation scope | 15min | Reduce layout thrash |
| 5 | Reduce initial record fetch limit | 10min | Faster cold start |

**Verdict: SHIP after P0 fixes. P1/P2 are iterative improvements.**
