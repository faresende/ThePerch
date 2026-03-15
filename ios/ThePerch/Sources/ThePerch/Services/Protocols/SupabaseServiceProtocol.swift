import Foundation

/// Protocol defining the interface for Supabase data operations.
/// Enables dependency injection and mock implementations for testing/previews.
@MainActor
protocol SupabaseServiceProtocol: AnyObject {
    // MARK: - State

    var isAuthenticated: Bool { get }
    var isLoading: Bool { get }
    var error: SupabaseServiceError? { get }
    var connectionError: String? { get }
    var isOffline: Bool { get }

    // MARK: - Query Methods

    func fetchRecords(
        category: RecordCategory?,
        type: RecordType?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> [Record]

    func fetchAgents(forceRefresh: Bool) async throws -> [Agent]
    func fetchSections(forceRefresh: Bool) async throws -> [Section]
    func fetchHomeWidgets(forceRefresh: Bool) async throws -> [HomeWidget]
    func fetchTokenUsage(agentId: String?, days: Int) async throws -> [TokenUsage]

    // MARK: - Mutation Methods

    func updateRecordPin(id: UUID, pinned: Bool) async throws
    func updateSectionOrder(sections: [Section]) async throws
    func insertRecord(
        agentId: String,
        userId: UUID,
        type: RecordType,
        category: RecordCategory,
        title: String,
        data: [String: JSONValue],
        displayHint: DisplayHint
    ) async throws

    // MARK: - Authentication

    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String, displayName: String) async throws
    func signOut() async throws
    func restoreSession() async

    // MARK: - Realtime

    func subscribeToRecords(onChange: @escaping @MainActor @Sendable (SupabaseService.RealtimeRecordChange) -> Void) async throws
    func subscribeToAgents(onChange: @escaping @MainActor @Sendable (SupabaseService.RealtimeAction) -> Void) async throws
    func unsubscribeAll() async

    // MARK: - Cache

    func invalidateCache()

    // MARK: - Freshness

    var freshnessTracker: DataFreshnessTracker { get }
    var lastFetchTimes: [RecordCategory: Date] { get }
    var lastGlobalFetchTime: Date? { get }
    func minutesSinceLastFetch(category: RecordCategory?) -> Int?
}
