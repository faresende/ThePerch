import Foundation
import Combine
import Network
import Supabase
import Realtime

// MARK: - Error Types

/// Errors that can occur during Supabase operations.
enum SupabaseServiceError: LocalizedError, Sendable {
    case clientNotInitialized
    case authError(String)
    case queryError(String)
    case decodingError(String)
    case networkError(String)
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "Supabase client is not initialized"
        case .authError(let message):
            return "Authentication error: \(message)"
        case .queryError(let message):
            return "Query error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - Cache Entry

/// A time-stamped cache entry for avoiding redundant network requests within 30 seconds.
private struct CacheEntry<T> {
    let value: T
    let fetchedAt: Date

    var isStale: Bool {
        Date.now.timeIntervalSince(fetchedAt) > 30
    }
}

// MARK: - Data Freshness Tracking

/// Tracks when each data category was last fetched, for UI display and auto-refresh.
enum UrgencyTier {
    case fresh      // <5 min
    case stale      // >5 min — warning dot
    case warning    // >30 min — pulsing amber border
    case critical   // >2 hours — solid warning border
}

@Observable
@MainActor
final class DataFreshnessTracker {
    static let shared = DataFreshnessTracker()

    private(set) var lastFetchTimes: [String: Date] = [:]

    /// Auto-refresh threshold in seconds (5 minutes).
    let staleThreshold: TimeInterval = 300

    func recordFetch(for key: String) {
        lastFetchTimes[key] = Date.now
    }

    func isStale(_ key: String) -> Bool {
        guard let lastFetch = lastFetchTimes[key] else { return true }
        return Date.now.timeIntervalSince(lastFetch) > staleThreshold
    }

    func urgencyTier(for key: String) -> UrgencyTier {
        guard let lastFetch = lastFetchTimes[key] else { return .critical }
        let elapsed = Date.now.timeIntervalSince(lastFetch)
        if elapsed > 7200 { return .critical }
        if elapsed > 1800 { return .warning }
        if elapsed > 300 { return .stale }
        return .fresh
    }

    func relativeTimeString(for key: String) -> String? {
        guard let lastFetch = lastFetchTimes[key] else { return nil }
        let interval = Date.now.timeIntervalSince(lastFetch)
        let minutes = Int(interval / 60)
        if minutes < 1 {
            return "Updated just now"
        } else if minutes == 1 {
            return "Updated 1 min ago"
        } else {
            return "Updated \(minutes) min ago"
        }
    }
}

// MARK: - SupabaseService

/// A singleton service for managing Supabase interactions.
/// Connects to the real Supabase backend, with mock data fallback.
@MainActor
final class SupabaseService: ObservableObject, SupabaseServiceProtocol {
    static let shared = SupabaseService()

    // MARK: - Published Properties

    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: SupabaseServiceError?
    @Published var connectionError: String?
    @Published var isOffline: Bool = false

    // MARK: - Private Properties

    #if DEBUG
    /// Toggle to fall back to mock data during development only.
    private var useMockData = false
    #endif

    /// The Supabase client instance.
    private let client: SupabaseClient

    /// Active realtime channels for subscription management.
    private var recordsChannel: RealtimeChannelV2?
    private var agentsChannel: RealtimeChannelV2?

    /// Managed tasks for realtime stream listeners (cancelled on unsubscribe).
    private var realtimeTasks: [Task<Void, Never>] = []

    /// Tracks when each category was last fetched for data freshness.
    @Published var lastFetchTimes: [RecordCategory: Date] = [:]
    @Published var lastGlobalFetchTime: Date?

    /// Shared JSON decoder for Supabase responses (ISO8601 dates).
    private let recordDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Retry configuration
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0

    // MARK: - Cache

    private var sectionsCache: CacheEntry<[Section]>?
    private var recordsCache: [String: CacheEntry<[Record]>] = [:]
    private var agentsCache: CacheEntry<[Agent]>?
    private var homeWidgetsCache: CacheEntry<[HomeWidget]>?

    let freshnessTracker = DataFreshnessTracker.shared
    private let cacheService = CacheService.shared

    /// A default user ID for caching when auth is not enabled.
    private var cacheUserId: String {
        "default_user"
    }

    // MARK: - Initialization

    private init() {
        let config = AppConfig.shared
        self.client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.supabaseAnonKey
        )
        startNetworkMonitoring()
    }

    var databaseClient: SupabaseClient {
        client
    }

    // MARK: - Connection Test

    /// Tests a Supabase connection without affecting the shared service.
    /// Used by OnboardingView to validate credentials before saving.
    static func testConnection(url: String, anonKey: String) async throws {
        guard let supabaseURL = URL(string: url) else {
            throw URLError(.badURL)
        }
        let testClient = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: anonKey)
        // Try fetching 1 section — if this succeeds the credentials are valid
        let _: [Section] = try await testClient
            .from("sections")
            .select()
            .limit(1)
            .execute()
            .value
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        _ = withObservationTracking {
            NetworkMonitor.shared.isConnected
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOffline = !NetworkMonitor.shared.isConnected
                if NetworkMonitor.shared.isConnected {
                    self.connectionError = nil
                }
                self.startNetworkMonitoring()
            }
        }

        isOffline = !NetworkMonitor.shared.isConnected
        if NetworkMonitor.shared.isConnected {
            connectionError = nil
        }
    }

    // MARK: - Retry Logic

    /// Executes an async operation with exponential backoff retry (3 attempts).
    private func withRetry<T>(
        operation: String,
        body: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let result = try await body()
                self.connectionError = nil
                return result
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
#if DEBUG
                    print("[\(operation)] Attempt \(attempt + 1) failed, retrying in \(delay)s: \(error.localizedDescription)")
#endif
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        let finalError = lastError ?? SupabaseServiceError.unknownError("All retries exhausted")
        connectionError = finalError.localizedDescription
        throw finalError
    }

    // MARK: - Cache Helpers

    private func recordsCacheKey(category: RecordCategory?, type: RecordType?, limit: Int) -> String {
        "\(category?.rawValue ?? "all")_\(type?.rawValue ?? "all")_\(limit)"
    }

    /// Invalidates all caches.
    func invalidateCache() {
        sectionsCache = nil
        recordsCache.removeAll()
        agentsCache = nil
        homeWidgetsCache = nil
    }

    // MARK: - Authentication Methods

    /// Signs in a user with email and password.
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            self.isAuthenticated = true
            self.error = nil
            return
        }
        #endif

        do {
            try await client.auth.signIn(email: email, password: password)
            self.isAuthenticated = true
            self.error = nil
        } catch {
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Signs up a new user with email, password, and display name.
    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            self.isAuthenticated = true
            self.error = nil
            return
        }
        #endif

        do {
            try await client.auth.signUp(
                email: email,
                password: password,
                data: ["display_name": .string(displayName)]
            )
            self.isAuthenticated = true
            self.error = nil
        } catch {
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Signs out the current user.
    func signOut() async throws {
        #if DEBUG
        if useMockData {
            self.isAuthenticated = false
            self.error = nil
            return
        }
        #endif

        do {
            try await client.auth.signOut()
            self.isAuthenticated = false
            self.error = nil
            invalidateCache()
        } catch {
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Checks for an existing session and restores it.
    func restoreSession() async {
        #if DEBUG
        if useMockData {
            self.isAuthenticated = true
            return
        }
        #endif

        do {
            let session = try await client.auth.session
            self.isAuthenticated = true
#if DEBUG
            print("[SupabaseService] Session restored for user: \(session.user.id)")
#endif
        } catch {
            self.isAuthenticated = false
            print("[SupabaseService] No active session: \(error.localizedDescription)")
        }
    }

    // MARK: - Query Methods

    /// Fetches records with 30s cache and exponential backoff retry.
    func fetchRecords(
        category: RecordCategory? = nil,
        type: RecordType? = nil,
        limit: Int = 100,
        forceRefresh: Bool = false
    ) async throws -> [Record] {
        let cacheKey = recordsCacheKey(category: category, type: type, limit: limit)

        if !forceRefresh, let cached = recordsCache[cacheKey], !cached.isStale {
            return cached.value
        }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 300_000_000)
            var records = MockData.allRecords
            if let category { records = records.filter { $0.category == category } }
            if let type { records = records.filter { $0.type == type } }
            let result = Array(records.prefix(limit))
            recordsCache[cacheKey] = CacheEntry(value: result, fetchedAt: Date.now)
            return result
        }
        #endif

        do {
            let records: [Record] = try await withRetry(operation: "fetchRecords") { [client, recordDecoder] in
                var query = client.from("dashboard_records").select()
                if let category {
                    query = query.eq("category", value: category.rawValue)
                }
                if let type {
                    query = query.eq("type", value: type.rawValue)
                }
                let result = try await query
                    .order("created_at", ascending: false)
                    .limit(limit)
                    .execute()
                
                let rawArray = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] ?? []
                var records: [Record] = []
                for item in rawArray {
                    do {
                        let itemData = try JSONSerialization.data(withJSONObject: item)
                        let record = try recordDecoder.decode(Record.self, from: itemData)
                        records.append(record)
                    } catch {
                        #if DEBUG
                        print("[SupabaseService] Dropping malformed record: \(error)")
                        #endif
                    }
                }
                return records
            }

            recordsCache[cacheKey] = CacheEntry(value: records, fetchedAt: Date.now)

            // Persist to disk for offline access
            cacheService.saveRecords(records, category: category, userId: cacheUserId)

            if let category {
                lastFetchTimes[category] = Date.now
                freshnessTracker.recordFetch(for: category.rawValue)
            } else {
                lastGlobalFetchTime = Date.now
                freshnessTracker.recordFetch(for: "all_records")
            }
            return records
        } catch {
            // Fallback to offline cache if network fetch fails
            if let cached = cacheService.loadRecords(category: category, userId: cacheUserId) {
#if DEBUG
                print("[SupabaseService] Network failed, using offline cache for \(category?.rawValue ?? "all")")
#endif
                var filtered = cached
                if let type { filtered = filtered.filter { $0.type == type } }
                let result = Array(filtered.prefix(limit))
                recordsCache[cacheKey] = CacheEntry(value: result, fetchedAt: Date.now)
                return result
            }
            throw error
        }
    }

    /// Fetches all active agents with 30s cache and retry.
    func fetchAgents(forceRefresh: Bool = false) async throws -> [Agent] {
        if !forceRefresh, let cached = agentsCache, !cached.isStale {
            return cached.value
        }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            let result = MockData.agents
            agentsCache = CacheEntry(value: result, fetchedAt: Date.now)
            return result
        }
        #endif

        let agents: [Agent] = try await withRetry(operation: "fetchAgents") { [client] in
            try await client.from("agents")
                .select()
                .eq("is_active", value: true)
                .execute()
                .value
        }
        agentsCache = CacheEntry(value: agents, fetchedAt: Date.now)
        freshnessTracker.recordFetch(for: "agents")
        return agents
    }

    /// Fetches token usage statistics with retry.
    func fetchTokenUsage(agentId: String? = nil, days: Int = 30) async throws -> [TokenUsage] {
        #if DEBUG
        if useMockData { return [] }
        #endif

        do {
            return try await withRetry(operation: "fetchTokenUsage") { [client] in
                var query = client.from("token_usage").select()
                if let agentId {
                    query = query.eq("agent_id", value: agentId)
                }
                return try await query
                    .order("date", ascending: false)
                    .limit(days)
                    .execute()
                    .value
            }
        } catch {
            connectionError = error.localizedDescription
            throw error
        }
    }

    /// Fetches all sections with 30s cache and retry.
    func fetchSections(forceRefresh: Bool = false) async throws -> [Section] {
        if !forceRefresh, let cached = sectionsCache, !cached.isStale {
            return cached.value
        }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            let result = MockData.sections
            sectionsCache = CacheEntry(value: result, fetchedAt: Date.now)
            return result
        }
        #endif

        do {
            let sections: [Section] = try await withRetry(operation: "fetchSections") { [client, recordDecoder] in
                let result = try await client.from("sections")
                    .select()
                    .order("sort_order", ascending: true)
                    .execute()
                return try recordDecoder.decode([Section].self, from: result.data)
            }

            sectionsCache = CacheEntry(value: sections, fetchedAt: Date.now)
            cacheService.saveSections(sections, userId: cacheUserId)
            freshnessTracker.recordFetch(for: "sections")
            return sections
        } catch {
            // Fallback to offline cache
            if let cached = cacheService.loadSections(userId: cacheUserId) {
#if DEBUG
                print("[SupabaseService] Network failed, using offline cache for sections")
#endif
                sectionsCache = CacheEntry(value: cached, fetchedAt: Date.now)
                return cached
            }
            throw error
        }
    }

    /// Fetches all home widget configurations with 30s cache and retry.
    func fetchHomeWidgets(forceRefresh: Bool = false) async throws -> [HomeWidget] {
        if !forceRefresh, let cached = homeWidgetsCache, !cached.isStale {
            return cached.value
        }

        #if DEBUG
        if useMockData { return [] }
        #endif

        let widgets: [HomeWidget] = try await withRetry(operation: "fetchHomeWidgets") { [client] in
            try await client.from("home_widgets")
                .select()
                .order("sort_order", ascending: true)
                .execute()
                .value
        }
        homeWidgetsCache = CacheEntry(value: widgets, fetchedAt: Date.now)
        return widgets
    }

    // MARK: - Mutation Methods

    /// Updates the pinned state of a record.
    func updateRecordPin(id: UUID, pinned: Bool) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        struct PinUpdate: Encodable { let pinned: Bool }

        do {
            try await client.from("dashboard_records")
                .update(PinUpdate(pinned: pinned))
                .eq("id", value: id.uuidString)
                .execute()
            recordsCache.removeAll()
        } catch {
            throw SupabaseServiceError.queryError(error.localizedDescription)
        }
    }

    /// Updates the sort order of sections.
    func updateSectionOrder(sections: [Section]) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        struct SectionUpdate: Encodable {
            let sortOrder: Int
            let isVisible: Bool
            enum CodingKeys: String, CodingKey {
                case sortOrder = "sort_order"
                case isVisible = "is_visible"
            }
        }

        for section in sections {
            do {
                try await client.from("sections")
                    .update(SectionUpdate(sortOrder: section.sortOrder, isVisible: section.isVisible))
                    .eq("id", value: section.id.uuidString)
                    .execute()
            } catch {
                throw SupabaseServiceError.queryError(error.localizedDescription)
            }
        }
        sectionsCache = nil
    }

    /// Updates the JSON data field of a record (e.g. toggling medication checkboxes).
    func updateRecordData(recordId: UUID, data: [String: JSONValue]) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        struct DataUpdate: Encodable {
            let data: [String: JSONValue]
        }

        do {
            try await client.from("dashboard_records")
                .update(DataUpdate(data: data))
                .eq("id", value: recordId.uuidString)
                .execute()
            recordsCache.removeAll()
            DecodingCache.shared.clear()
        } catch {
            throw SupabaseServiceError.queryError(error.localizedDescription)
        }
    }

    // MARK: - Insert Methods

    /// Inserts a new record into the dashboard_records table.
    /// Used by HealthKitSyncService to write health data from Apple Health.
    func insertRecord(
        agentId: String,
        userId: UUID,
        type: RecordType,
        category: RecordCategory,
        title: String,
        data: [String: JSONValue],
        displayHint: DisplayHint
    ) async throws {
        #if DEBUG
        if useMockData {
            print("[SupabaseService] Mock mode: would insert \(title) record")
            return
        }
        #endif

        struct NewRecord: Encodable {
            let agent_id: String
            let user_id: String
            let type: String
            let category: String
            let title: String
            let data: [String: JSONValue]
            let display_hint: String
            let pinned: Bool
        }

        let record = NewRecord(
            agent_id: agentId,
            user_id: userId.uuidString,
            type: type.rawValue,
            category: category.rawValue,
            title: title,
            data: data,
            display_hint: displayHint.rawValue,
            pinned: false
        )

        do {
            try await client.from("dashboard_records")
                .insert(record)
                .execute()
#if DEBUG
            print("[SupabaseService] Inserted record: \(title)")
#endif
            recordsCache.removeAll()
        } catch {
            print("[SupabaseService] insertRecord error: \(error)")
            throw SupabaseServiceError.queryError(error.localizedDescription)
        }
    }

    // MARK: - Realtime Subscriptions

    /// Action types from Supabase Realtime postgres_changes.
    enum RealtimeAction: String {
        case insert = "INSERT"
        case update = "UPDATE"
        case delete = "DELETE"
    }

    /// Payload for realtime record changes.
    struct RealtimeRecordChange: Sendable {
        let action: RealtimeAction
        let record: Record?
        let oldId: UUID?
    }

    /// Subscribes to realtime record changes on `dashboard_records`.
    /// Calls `onChange` on the main actor whenever an INSERT, UPDATE, or DELETE occurs.
    func subscribeToRecords(onChange: @escaping @MainActor @Sendable (RealtimeRecordChange) -> Void) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        // Remove existing channel if reconnecting
        if let existing = recordsChannel {
            await client.realtimeV2.removeChannel(existing)
        }

        let channel = client.realtimeV2.channel("dashboard_records_changes")

        let insertions = channel.postgresChange(InsertAction.self, table: "dashboard_records")
        let updates = channel.postgresChange(UpdateAction.self, table: "dashboard_records")
        let deletions = channel.postgresChange(DeleteAction.self, table: "dashboard_records")

        self.recordsChannel = channel

        await channel.subscribe()
#if DEBUG
        print("[SupabaseService] Subscribed to dashboard_records realtime")
#endif

        // Listen for insertions
        let insertTask = Task {
            for await insertion in insertions {
                guard !Task.isCancelled else { break }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let data = try? JSONSerialization.data(withJSONObject: insertion.record),
                   let record = try? decoder.decode(Record.self, from: data) {
                    await onChange(RealtimeRecordChange(action: .insert, record: record, oldId: nil))
                } else {
                    // Even if decode fails, notify so UI can refresh
                    await onChange(RealtimeRecordChange(action: .insert, record: nil, oldId: nil))
                }
            }
        }
        realtimeTasks.append(insertTask)

        // Listen for updates
        let updateTask = Task {
            for await update in updates {
                guard !Task.isCancelled else { break }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let data = try? JSONSerialization.data(withJSONObject: update.record),
                   let record = try? decoder.decode(Record.self, from: data) {
                    await onChange(RealtimeRecordChange(action: .update, record: record, oldId: nil))
                } else {
                    await onChange(RealtimeRecordChange(action: .update, record: nil, oldId: nil))
                }
            }
        }
        realtimeTasks.append(updateTask)

        // Listen for deletions
        let deleteTask = Task {
            for await deletion in deletions {
                guard !Task.isCancelled else { break }
                let oldId: UUID? = {
                    if let idStr = deletion.oldRecord["id"] as? String {
                        return UUID(uuidString: idStr)
                    }
                    return nil
                }()
                await onChange(RealtimeRecordChange(action: .delete, record: nil, oldId: oldId))
            }
        }
        realtimeTasks.append(deleteTask)
    }

    /// Subscribes to realtime agent status changes on `agents`.
    func subscribeToAgents(onChange: @escaping @MainActor @Sendable (RealtimeAction) -> Void) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        if let existing = agentsChannel {
            await client.realtimeV2.removeChannel(existing)
        }

        let channel = client.realtimeV2.channel("agents_changes")

        let changes = channel.postgresChange(AnyAction.self, table: "agents")

        self.agentsChannel = channel

        await channel.subscribe()
#if DEBUG
        print("[SupabaseService] Subscribed to agents realtime")
#endif

        let agentTask = Task {
            for await change in changes {
                guard !Task.isCancelled else { break }
                let actionStr = String(describing: type(of: change)).lowercased()
                let action: RealtimeAction = actionStr.contains("insert") ? .insert :
                    actionStr.contains("delete") ? .delete : .update
                await onChange(action)
            }
        }
        realtimeTasks.append(agentTask)
    }

    /// Unsubscribes from all realtime channels and cancels stream listener tasks.
    func unsubscribeAll() async {
        // Cancel all managed realtime tasks
        for task in realtimeTasks {
            task.cancel()
        }
        realtimeTasks.removeAll()

        if let channel = recordsChannel {
            await client.realtimeV2.removeChannel(channel)
            recordsChannel = nil
        }
        if let channel = agentsChannel {
            await client.realtimeV2.removeChannel(channel)
            agentsChannel = nil
        }
#if DEBUG
        print("[SupabaseService] Unsubscribed from all realtime channels")
#endif
    }

    /// Minutes since last fetch for a given category (nil = global).
    func minutesSinceLastFetch(category: RecordCategory? = nil) -> Int? {
        let date: Date?
        if let category {
            date = lastFetchTimes[category]
        } else {
            date = lastGlobalFetchTime
        }
        guard let date else { return nil }
        return Int(Date.now.timeIntervalSince(date) / 60)
    }
}
