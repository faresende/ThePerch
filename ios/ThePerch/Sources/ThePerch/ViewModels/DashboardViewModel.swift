import Foundation
import Observation

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
    private(set) var deliveryRecords: [Record] = []
    private(set) var calendarRecords: [Record] = []
    private(set) var adminRecords: [Record] = []
    private(set) var bookmarkRecords: [Record] = []
    private(set) var travelRecords: [Record] = []

    /// Dynamic per-slug record lookup. Use this for any section slug not covered above.
    /// e.g. `recordsBySlug["finance"]` returns all records with category == "finance"
    private(set) var recordsBySlug: [String: [Record]] = [:]

    private func rebuildFilteredArrays() {
        // Known slugs → typed arrays (fast path for existing views)
        healthRecords   = allRecords.filter { $0.category == .health || $0.category == .workouts }
        deliveryRecords = allRecords.filter { $0.category == .deliveries }
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
    private let cacheService = CacheService.shared
    private let cacheUserId = "default_user"
    private let recentRecordsLimit = 500
    private let bookmarkBackfillLimit = 500

    // MARK: - Initialization

    init(supabaseService: SupabaseService? = nil) {
        self.supabaseService = supabaseService ?? .shared
    }

    // MARK: - Loading Data

    /// Loads cached data from disk immediately, then fetches fresh data from network.
    /// Views show cached data instantly (0ms perceived load), then update when fresh data arrives.
    func loadDashboard(forceRefresh: Bool = false) async {
        // Step 1: Load cached data instantly (synchronous disk read)
        let hadCachedData = loadCachedData()

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

        let (sections, widgets, records, bookmarkRecords) = await (sectionsResult, widgetsResult, recordsResult, bookmarkRecordsResult)

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
            self.allRecords = merged
            Self.preDecodeRecords(merged)
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
    }

    /// Loads cached records and sections from disk for instant display.
    /// Returns true if cached data was found and loaded.
    @discardableResult
    private func loadCachedData() -> Bool {
        var loaded = false

        // Load cached sections
        if sections.isEmpty, let cachedSections = cacheService.loadSections(userId: cacheUserId), !cachedSections.isEmpty {
            self.sections = cachedSections
            loaded = true
        }

        // Load cached records (all categories)
        if allRecords.isEmpty, let cachedRecords = cacheService.loadRecords(category: nil, userId: cacheUserId), !cachedRecords.isEmpty {
            self.allRecords = cachedRecords
            Self.preDecodeRecords(cachedRecords)
            loaded = true
        }

        if loaded {
            isShowingCachedData = true
            // Show "Last updated X ago" from cache metadata
            if let meta = cacheService.metadata(for: nil, userId: cacheUserId) {
                lastUpdatedString = "Last updated \(meta.relativeAgeString)"
            }
#if DEBUG
            print("[DashboardVM] Loaded cached data instantly")
#endif
        }

        return loaded
    }

    /// Pre-populates the DecodingCache for all records in a single pass.
    /// Front-loads ALL decoding after network response so views never pay the cost.
    private static func preDecodeRecords(_ records: [Record]) {
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

            let merged = Self.mergeRecords(try await recentRecords, with: try await bookmarkRecords)
            allRecords = merged
            error = nil
            Self.preDecodeRecords(merged)
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
                if record.category == .deliveries {
                    syncDeliveryLiveActivities()
                }
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
                if record.category == .deliveries {
                    syncDeliveryLiveActivities()
                }
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

    /// Syncs Live Activities using already-loaded delivery records.
    private func syncDeliveryLiveActivities() {
        let activeDeliveries = deliveryRecords.compactMap { record -> DeliveryData? in
            guard let d = record.asDelivery() else { return nil }
            let s = d.status.lowercased().replacingOccurrences(of: " ", with: "_")
            guard s == "in_transit" || s == "shipped" || s == "out_for_delivery" || s == "processing" || s == "ordered" else { return nil }
            return d
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
