# The Perch — Software Engineering Review

**Reviewer:** Senior Engineering Review (VP of Engineering perspective)
**Date:** March 8, 2026
**Codebase:** ~11,800 lines across 50+ Swift files
**Scope:** Full codebase review — architecture, security, performance, quality, production readiness

---

## Executive Summary

The Perch is a well-structured SwiftUI personal dashboard app with clean separation of concerns, a thoughtful design system, and good use of modern Swift patterns (@Observable, async/await). For a personal project, the foundation is solid. However, there are **critical security gaps** (hardcoded user ID, bypassed auth, exposed API keys), **architectural debt** (duplicated files, singletons everywhere, no DI), and **data layer risks** (silent mock fallback, no offline support, decode-and-discard errors) that would block any production deployment and could cause subtle data loss even for personal use.

**Bottom line:** The app *works* as a prototype dashboard. To ship confidently — even for personal use — you need to fix the P0 security issues, remove the mock data fallback trap, and add basic error surfacing. Everything else is polish.

### Severity Distribution
- **P0 (blocks shipping / security):** 7 findings
- **P1 (high impact):** 11 findings
- **P2 (polish):** 10 findings

---

## 1. Architecture & Patterns

### 1.1 [P1] Mixed Observation Patterns — `@Observable` vs `ObservableObject` | Size: M

**Files:** `SupabaseService.swift`, `NotificationService.swift`, `AuthViewModel.swift`, `DashboardViewModel.swift`

**Issue:** `SupabaseService` uses `ObservableObject` with `@Published`, while `AuthViewModel`, `DashboardViewModel`, and `SectionViewModel` use the newer `@Observable` macro. `NotificationService` also uses `ObservableObject`. This creates two observation systems running in parallel.

**Why it matters:** Views consuming `@Observable` objects use `@Environment(Type.self)`, while `ObservableObject` types need `@EnvironmentObject` or `@ObservedObject`. You're currently injecting `SupabaseService.shared` directly in init calls (not via environment), so the `@Published` properties on `SupabaseService` are never actually observed by any view. This means `isLoading` and `error` on the service are dead properties from the UI's perspective.

**Fix:** Migrate `SupabaseService` and `NotificationService` to `@Observable`, or (better) stop exposing observable state from the service layer entirely — ViewModels should own all UI-facing state, and services should be plain classes that return data.

```swift
// Before: SupabaseService mixes concerns
@MainActor
final class SupabaseService: ObservableObject {
    @Published var isAuthenticated: Bool = false  // Never observed by any View
    @Published var isLoading: Bool = false         // Never observed by any View
    ...
}

// After: Services return data, ViewModels own state
final class SupabaseService {  // Not ObservableObject
    func fetchRecords(...) async throws -> [Record] { ... }
}
```

### 1.2 [P1] Pervasive Singleton Pattern Without DI | Size: L

**Files:** `SupabaseService.swift`, `NotificationService.swift`, `EventKitService.swift`, `HealthKitService.swift`, `HealthKitSyncService.swift`, `DeliveryLiveActivityManager.swift`, `DataFreshnessTracker.swift`

**Issue:** Every service is a `static let shared` singleton accessed directly: `SupabaseService.shared`, `NotificationService.shared`, etc. ViewModels accept the service via init parameter (good!) but default to `.shared` (bad — makes testing require global state mutation).

**Why it matters:**
- Unit testing is effectively impossible — you can't inject mocks without protocol abstractions
- Service lifecycle is unmanaged — singletons live forever, even when the user logs out
- Makes it impossible to run two instances (e.g., for preview vs. production)

**Fix:** Define protocols for each service, inject via initializer, and provide `.shared` only at the composition root (ThePerchApp).

```swift
protocol RecordFetching: Sendable {
    func fetchRecords(category: RecordCategory?, type: RecordType?, limit: Int, forceRefresh: Bool) async throws -> [Record]
}

// SupabaseService conforms to RecordFetching
// MockRecordService conforms to RecordFetching for tests
```

### 1.3 [P2] Duplicate RecordDetailView Files | Size: S

**Files:** `Views/Cards/RecordDetailView.swift` (line 6969), `Views/Detail/RecordDetailView.swift` (line 7450)

**Issue:** Two separate `RecordDetailView` files exist with overlapping implementations. Only one can compile — the other is either dead code or causes a build conflict.

**Fix:** Delete the duplicate. Keep the one in `Views/Detail/` (it appears more complete) and remove `Views/Cards/RecordDetailView.swift`.

### 1.4 [P2] Duplicate DeliveryActivityAttributes | Size: S

**Files:** `DeliveryActivityAttributes.swift` (root), `PerchSharedKit/DeliveryActivityAttributes.swift`

**Issue:** The same struct is defined in two files. The root-level one should be deleted — the `PerchSharedKit` version is the correct location for sharing between app and widget targets.

**Fix:** Delete `ios/ThePerch/DeliveryActivityAttributes.swift`.

### 1.5 [P2] Views Doing Data Loading Directly | Size: M

**Files:** `AdminView.swift`, `HomeView.swift`

**Issue:** `AdminView` and `HomeView` contain their own `@State` properties for data (`agents`, `records`, `costRecords`) and call `SupabaseService.shared` directly in `loadData()` methods within the view. This bypasses the ViewModel pattern used elsewhere (`SectionViewModel`, `HealthViewModel`).

**Why it matters:** Business logic (sorting agents, filtering costs, determining gateway status) is mixed into the view body. This is untestable and creates inconsistency — some views use ViewModels, others don't.

**Fix:** Create `AdminViewModel` and promote `HomeView`'s data loading into a `HomeViewModel`. Match the pattern already established by `HealthViewModel` and `SectionViewModel`.

### 1.6 [P2] Hardcoded Agent Emoji/Name Mapping in Multiple Places | Size: S

**Files:** `WidgetRouter.swift` (lines ~agentEmojiForId/agentNameForId), `AdminView.swift` (same functions)

**Issue:** Agent emoji and name resolution is duplicated across `WidgetRouter` and `AdminView` with hardcoded switch statements. `AdminView` at least tries to look up from fetched agents first, but the fallback is identical copy-paste.

**Fix:** Move to a shared utility or make it a computed property on the `Agent` model.

---

## 2. Security

### 2.1 [P0] Auth Completely Bypassed | Size: S

**File:** `ThePerchApp.swift` (lines 3561-3586)

**Issue:** The auth gate is commented out:
```swift
// TODO: Re-enable auth gate once Supabase Auth user is created
// if authViewModel.isAuthenticated {
MainTabView()
// } else {
//     AuthView()
// }
```

The entire app runs without any authentication. Anyone with the binary can access all Supabase data.

**Why it matters:** Even for a personal app, the Supabase anon key + no auth means any network request to your Supabase instance is unauthenticated. If someone obtains your anon key (which they can — see 2.2), they can read all your dashboard data unless RLS policies are properly configured AND enforce auth.

**Fix:** Create the Supabase auth user, un-comment the auth gate, and verify RLS policies require `auth.uid()` matching.

### 2.2 [P0] Supabase Credentials in Bundled Plist — Extractable from IPA | Size: M

**File:** `AppConfig.swift`

**Issue:** The Supabase URL and anon key are loaded from `Secrets.plist` bundled in the app, with fallbacks to `Info.plist` and environment variables. The `Secrets.plist` approach ships the file inside the IPA, which is trivially extractable (unzip the .ipa, read the plist).

**Why it matters:** The anon key is *designed* to be public (it's the equivalent of a publishable key), but ONLY when RLS is properly configured. With auth bypassed (2.1), the anon key effectively grants full read access to your tables.

**Fix:**
1. **Immediate:** Re-enable auth (2.1) and verify RLS policies
2. **Better:** Use Xcode build configurations with `xcconfig` files (not checked into source control) to inject the URL/key at build time via `$(SUPABASE_URL)` in Info.plist
3. Ensure `Secrets.plist` is in `.gitignore`

### 2.3 [P0] Hardcoded User ID in HealthKitSyncService | Size: S

**File:** `HealthKitSyncService.swift`

```swift
private let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
```

**Issue:** Fábio's Supabase user ID is hardcoded directly in the sync service. This means:
1. If auth is ever enabled, this won't use the authenticated user's ID
2. The UUID is force-unwrapped — if the string is ever malformed, crash

**Fix:** Retrieve the user ID from the authenticated session: `client.auth.session.user.id`. Pass it through the service layer rather than hardcoding.

### 2.4 [P0] No RLS Validation or User Scoping in Queries | Size: M

**File:** `SupabaseService.swift`

**Issue:** No query includes a `user_id` filter. The app relies entirely on Supabase RLS to scope data to the current user. But with auth bypassed, RLS has no `auth.uid()` to match against.

**Why it matters:** If RLS policies use `auth.uid() = user_id`, they'll fail silently (return empty sets) or — worse — if RLS is permissive, return ALL users' data.

**Fix:**
1. Re-enable auth
2. Add explicit `.eq("user_id", value: currentUserId)` as a defense-in-depth measure
3. Audit RLS policies on every table (`dashboard_records`, `agents`, `sections`, `home_widgets`, `token_usage`)

### 2.5 [P0] Share Extension Credentials Not Populated | Size: M

**Files:** `MainAppIntegration.swift`, `ShareSupabaseClient.swift`, `SharedConstants.swift`

**Issue:** The Share Extension architecture is well-designed (shared keychain via App Group), but `MainAppIntegration.storeSharedSupabaseCredentials()` is never called anywhere in the main app. The share extension will fail at runtime because there are no credentials in the shared keychain.

**Why it matters:** Users will try to share a URL from Safari, see an error, and have no idea why.

**Fix:** Call `storeSharedSupabaseCredentials()` after successful authentication in the auth flow.

### 2.6 [P0] `fatalError` in AppConfig Crashes App on Missing Config | Size: S

**File:** `AppConfig.swift`

```swift
guard let url = URL(string: Self.getConfigValue(key: "SUPABASE_URL")) else {
    fatalError("Invalid Supabase URL in configuration")
}
...
if supabaseAnonKey.isEmpty {
    fatalError("Supabase anon key is not configured")
}
```

**Issue:** If `Secrets.plist` is missing or misconfigured, the app crashes on launch with no recovery path.

**Fix:** Use a graceful failure mode — show an error screen explaining the configuration issue, or use `preconditionFailure` with a clear message in debug and a fallback in release.

### 2.7 [P0] Force-Unwrap on UserID Will Crash | Size: S

**File:** `HealthKitSyncService.swift`

```swift
private let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
```

**Fix:** Use a `guard let` or make it a computed property that reads from the auth session.

---

## 3. Performance

### 3.1 [P1] Repeated JSON Encode-Decode on Every `asX()` Call | Size: M

**File:** `Record.swift` — `decodeData(as:)`, called from `DataPayloads.swift` extensions

**Issue:** Every call to `record.asMeasurement()`, `record.asDelivery()`, etc. does a full JSON encode of the `data` field and then decodes it into the target type:

```swift
func decodeData<T: Decodable>(as type: T.Type) -> T? {
    let encoder = JSONEncoder()
    guard let jsonData = try? encoder.encode(data) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(T.self, from: jsonData)
}
```

This is called multiple times per record in the same view render cycle. For example, `HomeView.smartOrderedRecords` calls `record.asDelivery()` and `record.asMeasurement()` and `record.asEvent()` repeatedly in filter closures — potentially hundreds of encode/decode cycles per frame.

**Why it matters:** On a list of 50 records, the smart ordering logic alone could trigger 150+ JSON encode/decode cycles. This won't freeze the UI, but it's wasteful CPU and battery.

**Fix:** Cache the decoded result. Either:
1. Make `Record` a class with lazy decoded properties
2. Use a computed cache dictionary keyed by record ID
3. Decode once at fetch time and store typed payloads alongside the record

```swift
// Option: Lazy cached decoding
private var _decodedCache: [String: Any] = [:]
func decodeData<T: Decodable>(as type: T.Type) -> T? {
    let key = String(describing: type)
    if let cached = _decodedCache[key] as? T { return cached }
    // ... decode and store ...
}
```

### 3.2 [P1] NumberFormatter Created on Every Cell Render | Size: S

**Files:** `RecordDetailView.swift` — `formattedNumber()`, `ChartCard.swift`, `MacrosCard.swift`

**Issue:** `NumberFormatter()` is instantiated inside `formattedNumber()` which is called per-cell in lists and charts. `NumberFormatter` is expensive to create.

**Fix:** Make it a `static let`:
```swift
private static let numberFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 2
    return f
}()
```

### 3.3 [P1] DateFormatter Created Repeatedly | Size: S

**Files:** `DateFormatting.swift`, `HomeView.swift` (todaysCaloriesRecord), `CalendarView.swift`, `HealthViewModel.swift`

**Issue:** `DateFormatter` is created inside computed properties that run on every view evaluation. Both `HomeView.todaysCaloriesRecord` and `HomeView.greetingText` create formatters inline.

**Fix:** Hoist all DateFormatters to static properties. The `HealthViewModel.contextDateFormatter` shows the correct pattern — apply it everywhere.

### 3.4 [P1] Timer-Based Atmosphere Runs Even When View Not Visible | Size: S

**File:** `TimeOfDayAtmosphere.swift`

**Issue:** The `Timer.publish(every: 60)` runs continuously once the view appears, even if the app is in the background or the view is not on screen.

**Fix:** Use `onAppear`/`onDisappear` to start/stop the timer, or use `TimelineView(.periodic(from: .now, by: 60))` which SwiftUI manages automatically.

### 3.5 [P2] No Pagination — All Records Fetched at Once | Size: M

**File:** `SupabaseService.fetchRecords(limit: 100)`

**Issue:** Every section fetches up to 100 records in a single query. As data accumulates, this will grow. `HomeView` fetches 50 records of ALL categories, then filters in-memory.

**Fix:** For now this is fine for a single user. When records exceed ~500, implement cursor-based pagination with `range()` on the Supabase query.

### 3.6 [P2] Smart Ordering Runs on Every SwiftUI Evaluation | Size: S

**File:** `HomeView.swift` — `smartOrderedRecords` computed property

**Issue:** `smartOrderedRecords` is a computed property in the view body's call chain. It iterates through all records multiple times with multiple filter/sort operations. On every state change (even unrelated ones), SwiftUI may re-evaluate this.

**Fix:** Move to a ViewModel and compute only when `records` actually changes, storing the result.

---

## 4. Error Handling

### 4.1 [P0] Silent Fallback to Mock Data Masks Real Failures | Size: M

**File:** `SupabaseService.swift` — `fetchRecords()`, `fetchAgents()`, `fetchSections()`

**Issue:** When a network request fails after 3 retries, the service silently flips `useMockData = true` and serves mock data:

```swift
} catch {
    print("[SupabaseService] fetchRecords error: \(error)")
    useMockData = true
    return try await fetchRecords(category: category, type: type, limit: limit, forceRefresh: true)
}
```

**Why this is catastrophic:**
1. The user sees data, but it's **fake**. They think their dashboard is working when it's showing hardcoded mock records.
2. Once `useMockData` flips to `true`, it stays true for the entire app session. ALL subsequent queries serve mock data — even if the network recovers.
3. There is no UI indicator that the app is in mock mode.
4. A single transient network error (Wi-Fi handoff, background/foreground transition) permanently corrupts the session's data.

**Fix:**
1. **Remove the automatic mock fallback entirely in production.** Mock data should only be available in `#if DEBUG` / Preview contexts.
2. Surface the error to the UI via the ViewModel's `error` property.
3. Let the user retry manually (pull-to-refresh already exists).

```swift
// After (clean failure)
} catch {
    print("[SupabaseService] fetchRecords error: \(error)")
    throw SupabaseServiceError.networkError(error.localizedDescription)
}
```

### 4.2 [P1] Errors Logged to Console But Never Surfaced | Size: M

**Files:** Multiple — `HomeView.swift`, `AdminView.swift`, all `catch` blocks

**Issue:** Many errors are caught, printed to console, and then the function continues with empty data:

```swift
// HomeView.loadData
} catch {
    print("[HomeView] Failed to load records: \(error)")
    records = []  // Silent failure — user sees empty screen
}
```

`AdminView` is better (it has `loadError` state), but `HomeView`, `CalendarView`, `DeliveriesView`, and `BookmarksView` swallow errors.

**Fix:** Add error state to views or ViewModels that don't have it. Show an error banner with retry (like `AdminView` already does).

### 4.3 [P1] `decodeData()` Silently Returns nil on Malformed JSON | Size: M

**File:** `Record.swift`

**Issue:** `decodeData(as:)` uses `try?` for both encoding and decoding, converting all errors to `nil`:

```swift
guard let jsonData = try? encoder.encode(data) else { return nil }
return try? decoder.decode(T.self, from: jsonData)
```

If a record's data field has a typo in a key name, or a string where a number is expected, the decode silently fails. The record becomes invisible in the UI — it exists in the database but the app can't render it.

**Fix:** Add debug logging on decode failure:
```swift
func decodeData<T: Decodable>(as type: T.Type) -> T? {
    guard let jsonData = try? encoder.encode(data) else { return nil }
    do {
        return try decoder.decode(T.self, from: jsonData)
    } catch {
        #if DEBUG
        print("[Record] Failed to decode \(T.self) for record \(id): \(error)")
        #endif
        return nil
    }
}
```

### 4.4 [P2] AuthViewModel Observer Uses NotificationCenter But Nobody Posts | Size: S

**File:** `AuthViewModel.swift`

**Issue:** The auth observer listens for `NSNotification.Name("SupabaseAuthStateChanged")`, but nothing in the codebase posts this notification. The observer task runs forever doing nothing.

**Fix:** Either implement the notification posting in `SupabaseService` when auth state changes, or use the Supabase SDK's built-in auth state listener: `client.auth.onAuthStateChange`.

### 4.5 [P2] Share Extension Error UX Is Minimal | Size: S

**File:** `ShareExtensionView.swift`

**Issue:** When saving fails, the error message shows `error.localizedDescription` which for network errors is often unhelpful ("The operation couldn't be completed"). No retry button is offered after failure.

**Fix:** Map common errors to user-friendly messages and add a retry button.

---

## 5. Code Quality

### 5.1 [P1] Massive Mock Data File — 500+ Lines of Handcrafted Test Data | Size: M

**File:** `MockData.swift`

**Issue:** 500+ lines of manually constructed mock data with hardcoded UUIDs, dates, and JSON. This is tightly coupled to the current data model — any schema change requires updating all mock records manually.

**Why it matters:** Mock data maintenance becomes a tax on every model change. It's also not useful for testing because the data is static and doesn't cover edge cases.

**Fix:**
1. Create factory methods: `Record.mock(type: .delivery, title: "Test")` with sensible defaults
2. Move mock data into a `#if DEBUG` target or a separate test module
3. For SwiftUI previews, use a `PreviewSupabaseService` that returns factory-generated data

### 5.2 [P1] TODO Debt | Size: S

**Files:** Multiple

Outstanding TODOs found:
- `AppConfig.swift`: "Load these from a Secrets.plist file or environment variables"
- `ShareExtensionView.swift`: "Add actual favicon fetching here"
- `SupabaseService.swift`: "Implement batch widget update"

The `AppConfig` TODO is the most concerning — it suggests the current credential loading approach is known to be temporary.

**Fix:** Triage and address or convert to GitHub issues with clear ownership.

### 5.3 [P2] Inconsistent Date Extension vs Utility | Size: S

**Files:** `DateFormatting.swift`, `Record.swift` (`relativeTime` property), `Agent.swift`

**Issue:** Date formatting exists in three places:
1. `DateFormatting` utility enum with static functions
2. `Record.relativeTime` computed property (reimplements the same logic)
3. `Agent` model uses `.relativeTime` (different extension, not shown)

**Fix:** Use `DateFormatting.relativeTime(from:)` everywhere. Remove the duplicate `relativeTime` computed property on `Record`.

### 5.4 [P2] Dead Code — ContentView.swift | Size: S

**File:** `ContentView.swift`

```swift
/// This file is kept for backward compatibility but the real UI is in MainTabView.
struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}
```

This file serves no purpose — `ThePerchApp` uses `MainTabView()` directly. Delete it.

### 5.5 [P2] Settings View Toggles Are Non-Functional | Size: S

**File:** `SettingsView.swift`

**Issue:** The "Notifications" and "Dark Mode" toggles use local `@State` with empty `onChange` closures (`{ _ in }`). They don't persist or do anything.

**Fix:** Either implement the functionality or remove the toggles to avoid user confusion.

---

## 6. Data Layer

### 6.1 [P1] Cache Invalidation Is All-or-Nothing | Size: M

**File:** `SupabaseService.swift`

**Issue:** `recordsCache.removeAll()` is called after any mutation (pin update, insert). This invalidates the cache for ALL categories, forcing full re-fetches of everything.

**Fix:** Invalidate only the affected cache key:
```swift
func updateRecordPin(id: UUID, pinned: Bool) async throws {
    // ... update ...
    // Invalidate only relevant cache entries
    for key in recordsCache.keys {
        recordsCache.removeValue(forKey: key)
    }
    // Or better: update the cached record in-place
}
```

### 6.2 [P1] No Offline Support or Data Persistence | Size: L

**Issue:** The app has zero offline capability. If there's no network connection, every view shows either skeleton loaders or (worse) mock data (see 4.1). There's no local database, no Core Data, no SwiftData, no file-based cache.

**Why it matters:** On subway, airplane, or weak connectivity, the app is useless.

**Fix (if needed):** For a personal dashboard, consider persisting the last-fetched data to disk using `Codable` + `FileManager`, or adopt SwiftData for structured caching. Show cached data with a "last updated" indicator when offline.

### 6.3 [P1] Realtime Subscription Error Recovery | Size: M

**File:** `SupabaseService.swift` — `subscribeToRecords()`, `subscribeToAgents()`

**Issue:** If the realtime WebSocket connection drops, there's no reconnection logic. The `for await` loops will end silently, and the app will stop receiving live updates without any indication to the user.

**Fix:** Wrap subscription setup in a retry loop that re-subscribes on connection loss. Or use the Supabase SDK's built-in reconnection if available.

### 6.4 [P2] Widget Uses Static Data | Size: M

**File:** `PerchQuickGlanceWidget.swift`

**Issue:** The widget `getTimeline()` returns hardcoded placeholder data:
```swift
let entry = PerchQuickGlanceEntry(
    date: .now,
    caloriesPercent: "--%",
    nextEvent: "None",
    activeDeliveries: 0
)
```

**Fix:** Read from an App Group shared `UserDefaults` or file that the main app updates after each data fetch.

---

## 7. Concurrency

### 7.1 [P1] @MainActor on Everything — Including Network Calls | Size: M

**Files:** `SupabaseService.swift`, `HealthKitSyncService.swift`, `EventKitService.swift`

**Issue:** `SupabaseService`, `HealthKitSyncService`, and `EventKitService` are all annotated `@MainActor`. This means all network calls, JSON decoding, and data processing run on the main thread.

**Why it matters:** Network calls themselves are async (they suspend), so they don't *block* the main thread during I/O. However, JSON decoding, retry logic, and cache manipulation DO run on the main actor. With 100 records × complex JSON decode, this could cause dropped frames.

**Fix:** Remove `@MainActor` from services. Use `nonisolated` for network/decode methods. Only switch to `@MainActor` when updating published state:

```swift
final class SupabaseService {  // No @MainActor
    nonisolated func fetchRecords(...) async throws -> [Record] {
        // Network + decode happens off main thread
        let records = try await client.from("dashboard_records")...
        return try decoder.decode([Record].self, from: result.data)
    }
}
```

### 7.2 [P1] Unmanaged Task Spawning in Realtime Listeners | Size: M

**File:** `SupabaseService.swift` — `subscribeToRecords()`

**Issue:** Three `Task { }` blocks are spawned inside `subscribeToRecords()` for insertions, updates, and deletions. These tasks are never stored, tracked, or cancelled. If `subscribeToRecords()` is called again (e.g., on reconnection), old tasks keep running alongside new ones — causing duplicate processing.

**Fix:** Store the tasks and cancel them before creating new ones:
```swift
private var realtimeTasks: [Task<Void, Never>] = []

func subscribeToRecords(...) async throws {
    // Cancel previous listeners
    realtimeTasks.forEach { $0.cancel() }
    realtimeTasks.removeAll()
    
    // Create new listeners
    let insertTask = Task { for await insertion in insertions { ... } }
    realtimeTasks.append(insertTask)
    // ...
}
```

### 7.3 [P2] Race Condition in `useMockData` Flag | Size: S

**File:** `SupabaseService.swift`

**Issue:** `useMockData` is a mutable `var` on a `@MainActor` class, so it's technically safe from data races. However, concurrent calls to `fetchRecords()` and `fetchAgents()` can both flip this flag independently. If `fetchRecords` fails and sets `useMockData = true`, then a concurrent `fetchAgents` call that was about to succeed will now use mock data instead.

**Fix:** Remove the automatic mock fallback (see 4.1). If mock mode is needed for development, make it a compile-time flag: `#if USE_MOCK_DATA`.

### 7.4 [P2] AuthViewModel Observer Task Leak | Size: S

**File:** `AuthViewModel.swift`

**Issue:** `authObserverTask` is stored but never cancelled. The `deinit` comment says "Cannot access main-actor isolated property from deinit" — so the task leaks.

**Fix:** Use `withTaskCancellationHandler` or store the task as `nonisolated` and cancel in `deinit`.

---

## 8. Production Readiness

### 8.1 [P0] No Tests | Size: XL

**Issue:** There are zero unit tests, zero UI tests, zero snapshot tests. No test targets visible in the project.

**Why it matters:** Every change is a leap of faith. The mock data fallback (4.1) makes this especially dangerous — you could break all network calls and never notice because mock data fills in seamlessly.

**Fix:** Start with:
1. **Model tests:** Test `Record.decodeData()` with valid and malformed JSON
2. **ViewModel tests:** Test `SectionViewModel.loadRecords()` with mock service
3. **Integration test:** Verify `SupabaseService` can connect and fetch (requires test Supabase project or mock server)

### 8.2 [P1] No Crash Reporting or Analytics | Size: M

**Issue:** No crash reporting (Sentry, Firebase Crashlytics, etc.) and no analytics. If the app crashes in production, you'll have no way to know unless you're actively using it at the time.

**Fix:** Add a lightweight crash reporter. For a personal app, even a simple `NSSetUncaughtExceptionHandler` that logs to a file would help.

### 8.3 [P1] No Network Reachability Awareness | Size: M

**Issue:** The app makes no distinction between "no data" and "no network." Both result in the same skeleton/empty state or mock data fallback.

**Fix:** Add `NWPathMonitor` to detect connectivity state. Show an "Offline" banner when disconnected, and auto-refresh when connectivity returns.

### 8.4 [P2] No App Transport Security Exceptions Audit | Size: S

**Issue:** Not reviewed, but ensure `NSAppTransportSecurity` in Info.plist doesn't have `NSAllowsArbitraryLoads = YES` for production.

### 8.5 [P2] Widget and Live Activity Not Integrated with Main App Data | Size: M

**Issue:** The widget shows static placeholder data (see 6.4). The Live Activity manager is wired up (`DeliveryLiveActivityManager`) but never called from any view or ViewModel after data loads.

**Fix:** Call `DeliveryLiveActivityManager.shared.sync(activeDeliveries:)` from the deliveries data loading path.

---

## 9. What's Done Well

Credit where it's due — there are several things this codebase gets right:

1. **Design System:** `PerchTheme` is comprehensive, well-organized, and consistently used. Adaptive dark/light mode, accessibility (reduce motion), WCAG-compliant contrast ratios. This is better than many production apps.

2. **Card Architecture:** The `WidgetRouter` → specialized card pattern is clean and extensible. Adding a new record type is straightforward.

3. **Skeleton Loading States:** Every section has matching skeleton loaders (`ShimmerEffect.swift`). This shows attention to perceived performance.

4. **Data Model Design:** The `Record` → `JSONValue` → typed decode pattern (`asMeasurement()`, `asDelivery()`) is flexible and handles the heterogeneous data well. The `DisplayHint` enum driving card selection is elegant.

5. **Freshness Tracking:** `DataFreshnessTracker` with urgency tiers and visual indicators is a thoughtful feature for a dashboard app.

6. **Haptic Feedback:** Consistent use of `PerchHaptics` across interactions. The `CardPressStyle` with scale animation is polished.

7. **Pull-to-Refresh:** Every data-driven view supports it.

8. **Retry Logic:** `withRetry` with exponential backoff in `SupabaseService` is solid (the problem is what happens AFTER retries exhaust — see 4.1).

---

## 10. Prioritized Implementation Roadmap

### Phase 1: Stop the Bleeding (Week 1) — Must Do
| # | Finding | Size | Priority |
|---|---------|------|----------|
| 1 | Remove silent mock data fallback (4.1) | M | P0 |
| 2 | Re-enable auth gate (2.1) | S | P0 |
| 3 | Remove hardcoded user ID (2.3) | S | P0 |
| 4 | Fix `fatalError` in AppConfig (2.6) | S | P0 |
| 5 | Delete duplicate files (1.3, 1.4) | S | P2 |
| 6 | Add decode error logging (4.3) | S | P1 |

### Phase 2: Structural Improvements (Weeks 2-3) — Should Do
| # | Finding | Size | Priority |
|---|---------|------|----------|
| 7 | Surface errors in all views (4.2) | M | P1 |
| 8 | Cache decoded payloads (3.1) | M | P1 |
| 9 | Hoist DateFormatter/NumberFormatter to statics (3.2, 3.3) | S | P1 |
| 10 | Fix unmanaged realtime tasks (7.2) | M | P1 |
| 11 | Remove @MainActor from services (7.1) | M | P1 |
| 12 | Wire up Live Activity manager (8.5) | M | P2 |
| 13 | Populate widget with real data (6.4) | M | P2 |

### Phase 3: Architecture & Quality (Weeks 4-6) — Nice to Have
| # | Finding | Size | Priority |
|---|---------|------|----------|
| 14 | Introduce protocols for service DI (1.2) | L | P1 |
| 15 | Create ViewModels for Admin/Home views (1.5) | M | P2 |
| 16 | Add basic unit test suite (8.1) | XL | P0* |
| 17 | Unify observation pattern (1.1) | M | P1 |
| 18 | Add offline data persistence (6.2) | L | P1 |
| 19 | Add crash reporting (8.2) | M | P1 |
| 20 | Add network reachability (8.3) | M | P1 |

*Tests are P0 in importance but can wait until after the immediate security fixes.*

### Not Recommended Right Now
- Full DI container / Syringe-style injection — overkill for a personal app
- Core Data migration — SwiftData or simple file cache is sufficient
- Complex pagination — wait until you have >500 records

---

## Appendix: File-by-File Quick Reference

| File | Key Issues |
|------|-----------|
| `AppConfig.swift` | fatalError on missing config, credentials in bundle |
| `SupabaseService.swift` | Silent mock fallback, @MainActor on network, unmanaged tasks |
| `ThePerchApp.swift` | Auth bypassed |
| `HealthKitSyncService.swift` | Hardcoded user ID, force-unwrap |
| `Record.swift` | Expensive decodeData(), duplicate relativeTime |
| `HomeView.swift` | Data loading in view, no error handling |
| `AdminView.swift` | Data loading in view, duplicated helper functions |
| `AuthViewModel.swift` | Dead observer task, never-posted notification |
| `MockData.swift` | 500+ lines of maintenance burden |
| `ContentView.swift` | Dead code |
| `SettingsView.swift` | Non-functional toggles |
| `DeliveryActivityAttributes.swift` | Duplicate file |
| `TimeOfDayAtmosphere.swift` | Timer runs when not visible |

---

*Review completed March 8, 2026. This document should be treated as a living artifact — update it as findings are addressed.*
