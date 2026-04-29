import Foundation
import Observation
import Supabase
import PostgREST

// MARK: - DashboardViewModel

/// Manages the state of the main dashboard screen.
/// Single source of truth for ALL records — fetches once, distributes to sections.
/// Also handles sections, widgets, loading, and realtime updates.
@Observable
@MainActor
final class DashboardViewModel {
    // MARK: - Published Properties

    var sections: [Section] = []
    var homeWidgets: [HomeWidget] = []
    var isLoading: Bool = false
    var error: SupabaseServiceError?

    /// Single source of truth: ALL records fetched in one request.
    /// Setting this rebuilds all filtered category arrays.
    var allRecords: [Record] = [] {
        didSet { rebuildFilteredArrays() }
    }

    // MARK: - Pre-filtered Record Arrays

    /// Records grouped by section slug. Driven by the sections array, not hardcoded enum cases.
    /// This means any new section added to Supabase is automatically handled.
    private(set) var healthRecords: [Record] = []
    private(set) var calendarRecords: [Record] = []
    private(set) var adminRecords: [Record] = []
    private(set) var bookmarkRecords: [Record] = []
    private(set) var travelRecords: [Record] = []

    /// Canonical tracked-package models from the orders + shipments tables.
    private(set) var trackedOrders: [OrderWithShipments] = []
    private(set) var trackedDeliveries: [DeliveryData] = []

    /// Today's BioChecha-generated insight for the daily card on
    /// Today tab. Nil before the agent has run for the day (typical
    /// pre-7am state) — the card shows an empty state in that case.
    private(set) var todayInsight: Insight?

    /// Last 7 nights of sleep duration in minutes, oldest first.
    /// Drives the sparkline on HealthSummaryHomeCard. Read directly
    /// from health_metrics (sleep_duration_min, source=8sleep).
    /// Empty when no data yet (early-days state).
    private(set) var recentSleepDurations: [SleepNight] = []

    struct SleepNight: Sendable, Equatable {
        let date: Date          // start-of-day (UTC) of the night ending
        let minutes: Double
    }

    /// Events read live from the device's Calendar via EventKit. Separate
    /// from `calendarRecords` (which is agent-populated via Mac cron) so
    /// the UI can merge both sources — iPhone-first, agents-second — and
    /// the UI keeps working on days the Mac cron is down.
    private(set) var eventKitEvents: [EventData] = []
    private(set) var eventKitPermissionStatus: EventKitPermissionStatus = .unknown

    enum EventKitPermissionStatus: Sendable {
        case unknown
        case granted
        case denied
    }

    /// Dynamic per-slug record lookup. Use this for any section slug not covered above.
    /// e.g. `recordsBySlug["finance"]` returns all records with category == "finance"
    private(set) var recordsBySlug: [String: [Record]] = [:]

    private func rebuildFilteredArrays() {
        // Known slugs → typed arrays (fast path for existing views)
        healthRecords   = allRecords.filter { $0.category == .health || $0.category == .workouts }
        calendarRecords = allRecords.filter { $0.category == .calendar }
        adminRecords    = allRecords.filter { $0.category == .admin }
        bookmarkRecords = allRecords.filter { $0.category == .bookmarks }
        travelRecords   = allRecords.filter { $0.category == .travel }

        // Dynamic grouping: group ALL records by their category raw value
        // This automatically handles any new section slug without code changes
        var bySlug: [String: [Record]] = [:]
        for record in allRecords {
            let slug = record.category.rawValue
            bySlug[slug, default: []].append(record)
        }
        recordsBySlug = bySlug
    }

    /// Agents are fetched separately (different table, admin-only).
    var agents: [Agent] = []

    /// When showing cached data before network response, this is the cache age string.
    var lastUpdatedString: String?

    /// True when displaying cached data that hasn't been refreshed from the network yet.
    var isShowingCachedData: Bool = false

    // MARK: - Private Properties

    private let supabaseService: SupabaseService
    private let ordersService: OrdersService
    private let insightsService: InsightsService
    private let cacheService = CacheService.shared
    private var cacheUserId: String { supabaseService.currentUserId ?? "unauthenticated" }
    private let recentRecordsLimit = 500
    private let bookmarkBackfillLimit = 500

    // MARK: - Initialization

    init(supabaseService: SupabaseService? = nil) {
        self.supabaseService = supabaseService ?? .shared
        self.ordersService = OrdersService(supabaseService: self.supabaseService)
        self.insightsService = InsightsService(supabaseService: self.supabaseService)
    }

    // MARK: - Loading Data

    /// Loads cached data from disk immediately, then fetches fresh data from network.
    /// Views show cached data instantly (0ms perceived load), then update when fresh data arrives.
    func loadDashboard(forceRefresh: Bool = false) async {
        // EventKit fetch is fully detached so it can't block the cold-
        // start path. On absolute first launch the system permission
        // modal blocks the EKEventStore call indefinitely, which used to
        // stall every Supabase fetch behind it. The calendar surfaces
        // are tolerant of arriving slightly later — they flash empty →
        // filled — so the trade is worth it.
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.loadEventKitEvents()
        }

        // Step 1: Load cached data — file IO + decode happen off-main so
        // the loadDashboard task doesn't block while disk + JSONDecoder
        // walk a 500-record cache (was 80–250 ms on main on cold launch).
        let hadCachedData = await loadCachedData()

        // Step 2: Fetch fresh data from network
        if !hadCachedData { isLoading = true }
        defer {
            isLoading = false
            isShowingCachedData = false
            lastUpdatedString = nil
        }

        // Fire all fetches in parallel
        async let sectionsResult: Result<[Section], Error> = {
            do { return .success(try await supabaseService.fetchSections(forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()
        async let widgetsResult: Result<[HomeWidget], Error> = {
            do { return .success(try await supabaseService.fetchHomeWidgets(forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()
        async let recordsResult: Result<[Record], Error> = {
            do { return .success(try await supabaseService.fetchRecords(limit: recentRecordsLimit, forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()
        async let bookmarkRecordsResult: Result<[Record], Error> = {
            do { return .success(try await supabaseService.fetchRecords(category: .bookmarks, limit: bookmarkBackfillLimit, forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()
        async let trackedOrdersResult: Result<[OrderWithShipments], Error> = {
            do { return .success(try await ordersService.fetchOrders(forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()
        async let todayInsightResult: Result<Insight?, Error> = {
            do { return .success(try await insightsService.fetchTodayDailyInsight()) }
            catch { return .failure(error) }
        }()
        async let sleepHistoryResult: Result<[SleepNight], Error> = {
            do { return .success(try await self.fetchRecentSleepDurations(days: 7)) }
            catch { return .failure(error) }
        }()

        let (sections, widgets, records, bookmarkRecords, trackedOrders) = await (
            sectionsResult,
            widgetsResult,
            recordsResult,
            bookmarkRecordsResult,
            trackedOrdersResult
        )
        let todayInsightAsync = await todayInsightResult
        switch todayInsightAsync {
        case .success(let i): self.todayInsight = i
        case .failure(let err):
#if DEBUG
            print("[DashboardVM] fetchTodayDailyInsight threw: \(err)")
#endif
            // Insights are non-load-bearing for the rest of the app —
            // a failure here shouldn't surface as an error banner.
            // Just leave todayInsight nil and the empty state renders.
        }

        switch await sleepHistoryResult {
        case .success(let nights): self.recentSleepDurations = nights
        case .failure(let err):
#if DEBUG
            print("[DashboardVM] fetchRecentSleepDurations threw: \(err)")
#endif
            // Sleep history is also non-load-bearing — health card
            // renders a "no data" sparkline state when empty.
        }

        switch sections {
        case .success(let loaded):
            self.sections = loaded
            self.error = nil
        case .failure(let err):
#if DEBUG
            print("[DashboardVM] fetchSections threw: \(err)")
#endif
            // Only set error if we have no cached data to show
            if self.sections.isEmpty {
                self.error = .unknownError(err.localizedDescription)
            }
        }

        switch widgets {
        case .success(let loaded):
            self.homeWidgets = loaded
        case .failure(let err):
#if DEBUG
            print("[DashboardVM] fetchHomeWidgets threw: \(err)")
#endif
        }

        switch records {
        case .success(let loaded):
            let merged = Self.mergeRecords(loaded, with: resultValue(bookmarkRecords))
            // Defensive: if the network returned zero records while our cache
            // had real data, and this wasn't an explicit force-refresh, treat
            // the empty response as suspect (most likely an expired-auth
            // silent-empty — the exact failure mode that blanked the Today
            // tab). Keep the cache so the user sees something, and log it so
            // we notice if the session-expiry fix upstream doesn't catch it.
            let cacheWasPopulated = !self.allRecords.isEmpty
            if merged.isEmpty, cacheWasPopulated, !forceRefresh {
#if DEBUG
                print("[DashboardVM] WARNING: network returned 0 records while cache had \(self.allRecords.count). Keeping cache. If auth is valid this means the server truly has no records — pull-to-refresh will clear the cache.")
#endif
                // Preserve allRecords; don't mutate.
            } else {
                self.allRecords = merged
                Self.preDecodeRecordsAsync(merged)
            }
            self.error = nil
        case .failure(let err):
#if DEBUG
            print("[DashboardVM] fetchRecords threw: \(err)")
#endif
            // Keep showing cached data if network fails
            if self.allRecords.isEmpty, self.error == nil {
                self.error = .unknownError(err.localizedDescription)
            }
        }

        switch trackedOrders {
        case .success(let loaded):
            self.trackedOrders = loaded
            self.trackedDeliveries = Self.activeForToday(loaded).map(\.trackedDeliveryData)
            syncDeliveryLiveActivities()
        case .failure(let err):
#if DEBUG
            print("[DashboardVM] fetchOrders threw: \(err)")
#endif
        }

        // EventKit fetch was kicked off detached at the top — no
        // longer awaited here so loadDashboard returns as soon as
        // the Supabase fetches resolve.
    }

    /// Marks an order delivered by the user. Persists to Supabase and
    /// optimistically updates local state so the Home deliveries card
    /// drops the item immediately. `orderId` comes from
    /// `DeliveryData.orderId` (a UUID string) so this is safe to call
    /// from views that only hold the legacy delivery shape.
    func markOrderAsDelivered(orderId: String) async {
        guard let uuid = UUID(uuidString: orderId) else {
#if DEBUG
            print("[DashboardVM] markOrderAsDelivered: invalid orderId \(orderId)")
#endif
            return
        }
        do {
            try await ordersService.markAsDelivered(orderId: uuid)
            // Optimistic local update — drop from trackedDeliveries
            // immediately so the Home card re-renders without waiting
            // for the fetch round-trip.
            if let index = trackedOrders.firstIndex(where: { $0.id == uuid }) {
                let updated = trackedOrders[index]
                self.trackedOrders[index] = updated  // force observer tick
                self.trackedDeliveries = Self
                    .activeForToday(self.trackedOrders)
                    .map(\.trackedDeliveryData)
            }
            // Then refresh the canonical state from the server.
            async let refreshed = ordersService.fetchOrders(forceRefresh: true)
            if let fresh = try? await refreshed {
                self.trackedOrders = fresh
                self.trackedDeliveries = Self.activeForToday(fresh).map(\.trackedDeliveryData)
                syncDeliveryLiveActivities()
            }
        } catch {
#if DEBUG
            print("[DashboardVM] markAsDelivered failed: \(error.localizedDescription)")
#endif
            self.error = .unknownError("Couldn't mark delivered: \(error.localizedDescription)")
        }
    }

    /// Pulls the device's upcoming calendar events via EventKit and merges
    /// them into `eventKitEvents`. Called from loadDashboard and safe to
    /// call again on refresh. Failures (permission denied, no calendars)
    /// are non-fatal — the app still renders the Supabase-sourced
    /// `calendarRecords` on their own.
    func loadEventKitEvents() async {
        do {
            let events = try await EventKitService.shared.fetchUpcomingEvents(days: 14)
            self.eventKitEvents = events.map { ekEvent in
                EventData(
                    title: ekEvent.title,
                    start: ekEvent.startDate,
                    end: ekEvent.endDate,
                    location: ekEvent.location,
                    agentNotes: nil
                )
            }
            self.eventKitPermissionStatus = .granted
        } catch {
#if DEBUG
            print("[DashboardVM] EventKit fetch failed: \(error.localizedDescription)")
#endif
            self.eventKitEvents = []
            self.eventKitPermissionStatus = .denied
        }
    }

    /// Loads cached records and sections from disk for instant display.
    /// Returns true if cached data was found and loaded.
    ///
    /// Disk read + JSONDecoder pass for the 500-record cache used to
    /// happen synchronously on the main actor (~80–250 ms on cold
    /// launch). Now runs on a detached, user-initiated Task so the
    /// loadDashboard caller can hand off to the network fetches as
    /// soon as the file IO begins. The two `cacheService.load*` reads
    /// are thread-safe as long as we don't race with a write — and
    /// the only writers are the post-fetch updaters that haven't run
    /// yet at this point in the cold-start flow.
    @discardableResult
    private func loadCachedData() async -> Bool {
        let userId = cacheUserId
        let cacheService = self.cacheService

        struct Loaded: Sendable {
            let sections: [Section]?
            let records: [Record]?
            let metaAge: String?
        }

        // Single ioQueue hop instead of three sequential ones — see
        // CacheService.loadDashboardBundle for rationale.
        let loaded = await Task.detached(priority: .userInitiated) { () -> Loaded in
            let bundle = cacheService.loadDashboardBundle(userId: userId)
            return Loaded(sections: bundle.sections, records: bundle.records, metaAge: bundle.metaAge)
        }.value

        var didLoad = false

        if sections.isEmpty, let s = loaded.sections, !s.isEmpty {
            self.sections = s
            didLoad = true
        }
        if allRecords.isEmpty, let r = loaded.records, !r.isEmpty {
            self.allRecords = r
            Self.preDecodeRecordsAsync(r)
            didLoad = true
        }

        if didLoad {
            isShowingCachedData = true
            if let age = loaded.metaAge {
                lastUpdatedString = "Last updated \(age)"
            }
#if DEBUG
            print("[DashboardVM] Loaded cached data instantly (off-main)")
#endif
        }
        return didLoad
    }

    /// Pre-populates the DecodingCache for all records in a single pass.
    /// Schedule a background pre-decode pass. Returns immediately so the
    /// caller can update UI without paying decode cost on the main thread.
    /// `Record.decodeData` writes into `DecodingCache.shared` (NSCache),
    /// which is thread-safe — racing with view-time decodes is fine
    /// (the worst case is a duplicated decode, never a corrupted cache).
    nonisolated private static func preDecodeRecordsAsync(_ records: [Record]) {
        guard !records.isEmpty else { return }
        Task.detached(priority: .utility) {
            preDecodeRecords(records)
        }
    }

    /// Front-loads ALL decoding after network response so views never pay the cost.
    /// `nonisolated` because it's safe to run off-main: every operation it
    /// performs is on Sendable / thread-safe state (Record values are value
    /// types, DecodingCache wraps NSCache, JSONValueDecoder is pure).
    nonisolated private static func preDecodeRecords(_ records: [Record]) {
        for record in records {
            switch record.category {
            case .health:
                if record.displayHint == .macrosBar {
                    _ = record.decodeData(as: MacrosData.self)
                } else {
                    _ = record.decodeData(as: MeasurementData.self)
                }
            case .nutrition:
                break
            case .workouts:
                _ = record.decodeData(as: WorkoutSessionData.self)
            case .deliveries:
                _ = record.decodeData(as: DeliveryData.self)
            case .calendar:
                _ = record.decodeData(as: EventData.self)
            case .bookmarks:
                _ = record.decodeData(as: BookmarkData.self)
            case .admin:
                switch record.type {
                case .costSummary:
                    _ = record.decodeData(as: CostSummaryData.self)
                case .status:
                    _ = record.decodeData(as: StatusData.self)
                case .checklist:
                    _ = record.decodeData(as: ChecklistData.self)
                case .textNote:
                    _ = record.decodeData(as: TextNoteData.self)
                case .command:
                    _ = record.decodeData(as: AdminCommandData.self)
                default:
                    break
                }
            case .legal:
                break
            case .travel:
                switch record.type {
                case .trip:
                    _ = record.decodeData(as: TripData.self)
                case .itinerary:
                    _ = record.decodeData(as: ItineraryData.self)
                case .travelAlert:
                    _ = record.decodeData(as: TravelAlertData.self)
                case .weatherForecast:
                    _ = record.decodeData(as: WeatherForecastData.self)
                case .travelTask:
                    _ = record.decodeData(as: TravelTaskData.self)
                default:
                    break
                }
            case .unknown:
                break
            }
        }
    }

    /// Refreshes only records (lighter than full loadDashboard).
    func refreshRecords(forceRefresh: Bool = true) async {
        let shouldShowLoading = allRecords.isEmpty
        if shouldShowLoading { isLoading = true }
        defer {
            if shouldShowLoading { isLoading = false }
        }

        do {
            async let recentRecords = supabaseService.fetchRecords(limit: recentRecordsLimit, forceRefresh: forceRefresh)
            async let bookmarkRecords = supabaseService.fetchRecords(category: .bookmarks, limit: bookmarkBackfillLimit, forceRefresh: forceRefresh)
            async let latestOrders = ordersService.fetchOrders(forceRefresh: forceRefresh)

            let merged = Self.mergeRecords(try await recentRecords, with: try await bookmarkRecords)
            allRecords = merged
            trackedOrders = try await latestOrders
            trackedDeliveries = Self.activeForToday(trackedOrders).map(\.trackedDeliveryData)
            syncDeliveryLiveActivities()
            error = nil
            Self.preDecodeRecordsAsync(merged)
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            print("[DashboardVM] refreshRecords threw: \(error)")
            self.error = .unknownError(error.localizedDescription)
        }
    }

    private static func mergeRecords(_ primary: [Record], with secondary: [Record]) -> [Record] {
        let combined = (primary + secondary).sorted { $0.createdAt > $1.createdAt }
        var seen = Set<UUID>()
        return combined.filter { seen.insert($0.id).inserted }
    }

    /// Fetch the last N nights of sleep_duration_min from health_metrics.
    /// One row per metric upsert, but Withings/8sleep emit one
    /// sleep_duration_min per night, so we just take the most recent
    /// `days` rows. Returned oldest-first for the sparkline.
    private func fetchRecentSleepDurations(days: Int) async throws -> [SleepNight] {
        struct Row: Decodable {
            let value: Double
            let measured_at: String   // raw — measured_at is timestamptz,
                                      // various ISO 8601 forms; parse below
        }
        let result = try await supabaseService.databaseClient
            .from("health_metrics")
            .select("value, measured_at")
            .eq("metric", value: "sleep_duration_min")
            .order("measured_at", ascending: false)
            .limit(days)
            .execute()
        let rows = try Self.sleepRowsDecoder.decode([Row].self, from: result.data)

        return rows
            .compactMap { row -> SleepNight? in
                guard let d = Self.parsePostgrestTimestamp(row.measured_at) else { return nil }
                return SleepNight(date: d, minutes: row.value)
            }
            .sorted { $0.date < $1.date }
    }

    /// Shared decoder for the simple Row payload above. Avoids rebuilding
    /// a JSONDecoder on every loadDashboard sleep-history fetch.
    private static let sleepRowsDecoder: JSONDecoder = {
        let d = JSONDecoder()
        // Row.measured_at is a String; we parse it ourselves with the
        // permissive ISO formatter below — leave dateDecodingStrategy
        // at its default (no-op for strings).
        return d
    }()

    /// Permissive ISO 8601 parser for PostgREST timestamptz strings.
    /// PostgREST emits with or without fractional seconds, with `Z` or
    /// `+00:00` offset. Phase 3 perf: cached formatters.
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasicFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parsePostgrestTimestamp(_ s: String) -> Date? {
        isoFractionalFormatter.date(from: s) ?? isoBasicFormatter.date(from: s)
    }

    /// Filter `OrderWithShipments` to the set that belongs on Today's
    /// deliveries summary. Mirrors HubTab Active section's semantics:
    ///
    ///   - Skip dismissed_by_user (Phase 1 corrections soft-delete)
    ///   - Skip manually-delivered (user marked it delivered already)
    ///   - Skip delivered (carrier confirmed)
    ///   - Skip exception / needs_review / issue (those live in Hub
    ///     Issues section, not the Today summary)
    ///
    /// Pre-correction-work behavior was to map every loaded order to
    /// trackedDeliveries unfiltered, which silently surfaced
    /// dismissed-by-user / digital orders on Today even though Hub
    /// hid them. Reconciles the two surfaces.
    private static func activeForToday(_ orders: [OrderWithShipments]) -> [OrderWithShipments] {
        orders.filter { o in
            if o.order.isDismissedByUser { return false }
            if o.order.isManuallyDelivered { return false }
            let status = (o.primaryShipment?.status ?? o.order.status).lowercased()
            if status == "delivered" { return false }
            if ["exception", "needs_review", "issue"].contains(status) { return false }
            return true
        }
    }

    private func resultValue(_ result: Result<[Record], Error>) -> [Record] {
        switch result {
        case .success(let value):
            return value
        case .failure(let err):
#if DEBUG
            print("[DashboardVM] bookmark backfill fetch threw: \(err)")
#endif
            return []
        }
    }

    /// Fetches agents separately (different table, admin-only).
    func loadAgents(forceRefresh: Bool = false) async {
        do {
            agents = try await supabaseService.fetchAgents(forceRefresh: forceRefresh)
        } catch {
            print("[DashboardVM] fetchAgents threw: \(error)")
        }
    }

    // MARK: - Section Management

    /// Reorders sections and persists the changes to the server.
    /// - Parameter reorderedSections: The sections in their new order.
    func reorderSections(_ reorderedSections: [Section]) async {
        var updatedSections = reorderedSections
        for index in updatedSections.indices {
            updatedSections[index].sortOrder = index
        }

        do {
            try await supabaseService.updateSectionOrder(sections: updatedSections)
            self.sections = updatedSections
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Toggles the visibility of a section.
    /// - Parameter sectionId: The ID of the section to toggle.
    func toggleSectionVisibility(sectionId: UUID) async {
        guard let index = sections.firstIndex(where: { $0.id == sectionId }) else { return }

        sections[index].isVisible.toggle()

        do {
            try await supabaseService.updateSectionOrder(sections: sections)
            self.error = nil
        } catch let error as SupabaseServiceError {
            // Revert on failure
            sections[index].isVisible.toggle()
            self.error = error
        } catch {
            sections[index].isVisible.toggle()
            self.error = .unknownError(error.localizedDescription)
        }
    }

    // MARK: - Widget Management

    /// Updates the visibility and position of home widgets.
    /// - Parameter updatedWidgets: The updated widget configurations.
    func updateWidgets(_ updatedWidgets: [HomeWidget]) async {
        self.homeWidgets = updatedWidgets
    }

    // MARK: - Record Actions

    /// Toggles the pinned state of a record.
    func toggleRecordPin(recordId: UUID) async {
        guard let index = allRecords.firstIndex(where: { $0.id == recordId }) else { return }

        let newPinnedState = !allRecords[index].pinned
        do {
            try await supabaseService.updateRecordPin(id: recordId, pinned: newPinnedState)
            allRecords[index].pinned = newPinnedState
        } catch {
            print("[DashboardVM] toggleRecordPin failed: \(error)")
        }
    }

    // MARK: - Realtime Subscriptions

    private let reconnectManager = RealtimeReconnectManager.shared

    /// Debounce task for coalescing rapid realtime fallback refreshes.
    private var refreshDebounceTask: Task<Void, Never>?

    /// Sets up realtime subscriptions to listen for dashboard changes.
    /// Merges changes locally (INSERT/UPDATE/DELETE) instead of full refetch.
    func setupRealtimeSubscriptions() async {
        do {
            try await supabaseService.subscribeToRecords { [weak self] change in
                guard let self else { return }
#if DEBUG
                print("[DashboardVM] Realtime record change: \(change.action)")
#endif
                Task { @MainActor [weak self] in
                    self?.mergeRealtimeChange(change)
                }
            }

            try await supabaseService.subscribeToAgents { [weak self] action in
                guard self != nil else { return }
#if DEBUG
                print("[DashboardVM] Realtime agent change: \(action)")
#endif
                Task { @MainActor [weak self] in
                    await self?.loadAgents(forceRefresh: true)
                }
            }

            reconnectManager.didConnect()
        } catch let error as SupabaseServiceError {
            self.error = error
            reconnectManager.didDisconnect { [weak self] in
                await self?.attemptRealtimeReconnect() ?? false
            }
        } catch {
            self.error = .unknownError(error.localizedDescription)
            reconnectManager.didDisconnect { [weak self] in
                await self?.attemptRealtimeReconnect() ?? false
            }
        }
    }

    /// Attempts to re-establish realtime subscriptions. Returns true on success.
    func attemptRealtimeReconnect() async -> Bool {
        do {
            await supabaseService.unsubscribeAll()
            try await supabaseService.subscribeToRecords { [weak self] change in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.mergeRealtimeChange(change)
                }
            }
            try await supabaseService.subscribeToAgents { [weak self] action in
                guard self != nil else { return }
                Task { @MainActor [weak self] in
                    await self?.loadAgents(forceRefresh: true)
                }
            }
            return true
        } catch {
            print("[DashboardVM] Realtime reconnect failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Merges a single realtime change into allRecords locally.
    /// Falls back to debounced full refetch only if the payload can't be decoded.
    private func mergeRealtimeChange(_ change: SupabaseService.RealtimeRecordChange) {
        switch change.action {
        case .insert:
            if let record = change.record {
                // Pre-decode the new record and insert at the front (newest first)
                Self.preDecodeRecords([record])
                allRecords.insert(record, at: 0)
                NotificationService.shared.handleRecordChange(record: record, action: .insert)
            } else {
                scheduleDebouncedRefresh()
            }

        case .update:
            if let record = change.record,
               let index = allRecords.firstIndex(where: { $0.id == record.id }) {
                // Pre-decode and replace in-place
                Self.preDecodeRecords([record])
                allRecords[index] = record
                NotificationService.shared.handleRecordChange(record: record, action: .update)
            } else {
                scheduleDebouncedRefresh()
            }

        case .delete:
            if let oldId = change.oldId {
                allRecords.removeAll { $0.id == oldId }
            } else {
                scheduleDebouncedRefresh()
            }
        }
    }

    /// Debounces rapid-fire realtime fallback refreshes into a single network call.
    /// When multiple realtime events fire rapidly (e.g., batch data push), this coalesces
    /// them into one refresh after 500ms of quiet.
    private func scheduleDebouncedRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            guard !Task.isCancelled else { return }
            await self?.refreshRecords()
        }
    }

    /// Tears down realtime subscriptions.
    func teardownRealtimeSubscriptions() async {
        await supabaseService.unsubscribeAll()
    }

    // MARK: - Live Activity Sync

    /// Syncs Live Activities using the canonical orders + shipments delivery projection.
    private func syncDeliveryLiveActivities() {
        let activeDeliveries = trackedDeliveries.filter { delivery in
            let normalized = delivery.status.lowercased().replacingOccurrences(of: " ", with: "_")
            return normalized == "in_transit"
                || normalized == "shipped"
                || normalized == "out_for_delivery"
                || normalized == "processing"
                || normalized == "ordered"
        }
        Task {
            await DeliveryLiveActivityManager.shared.sync(activeDeliveries: activeDeliveries)
        }
    }

    // MARK: - Error Handling

    /// Clears any error messages.
    func clearError() {
        self.error = nil
    }
}
