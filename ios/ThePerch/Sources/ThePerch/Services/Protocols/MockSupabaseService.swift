import Foundation

/// Mock implementation of SupabaseServiceProtocol for previews and testing.
@MainActor
final class MockSupabaseService: SupabaseServiceProtocol {
    // MARK: - State

    var isAuthenticated: Bool = true
    var isLoading: Bool = false
    var error: SupabaseServiceError?
    var connectionError: String?
    var isOffline: Bool = false

    let freshnessTracker = DataFreshnessTracker.shared
    var lastFetchTimes: [RecordCategory: Date] = [:]
    var lastGlobalFetchTime: Date?

    // MARK: - Mock Data

    var mockRecords: [Record] = []
    var mockAgents: [Agent] = []
    var mockSections: [Section] = []
    var mockHomeWidgets: [HomeWidget] = []
    var mockTokenUsage: [TokenUsage] = []

    // MARK: - Query Methods

    func fetchRecords(
        category: RecordCategory? = nil,
        type: RecordType? = nil,
        limit: Int = 100,
        forceRefresh: Bool = false
    ) async throws -> [Record] {
        var records = mockRecords
        if let category { records = records.filter { $0.category == category } }
        if let type { records = records.filter { $0.type == type } }
        return Array(records.prefix(limit))
    }

    func fetchAgents(forceRefresh: Bool = false) async throws -> [Agent] {
        mockAgents
    }

    func fetchSections(forceRefresh: Bool = false) async throws -> [Section] {
        mockSections
    }

    func fetchHomeWidgets(forceRefresh: Bool = false) async throws -> [HomeWidget] {
        mockHomeWidgets
    }

    func fetchTokenUsage(agentId: String? = nil, days: Int = 30) async throws -> [TokenUsage] {
        mockTokenUsage
    }

    // MARK: - Mutation Methods

    func updateRecordPin(id: UUID, pinned: Bool) async throws {}
    func updateSectionOrder(sections: [Section]) async throws {}
    func updateHomeWidgets(widgets: [HomeWidget]) async throws {}

    func insertRecord(
        agentId: String,
        userId: UUID,
        type: RecordType,
        category: RecordCategory,
        title: String,
        data: [String: JSONValue],
        displayHint: DisplayHint
    ) async throws {}

    // MARK: - Authentication

    func signIn(email: String, password: String) async throws {
        isAuthenticated = true
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        isAuthenticated = true
    }

    func signOut() async throws {
        isAuthenticated = false
    }

    func restoreSession() async {
        isAuthenticated = true
    }

    // MARK: - Realtime

    func subscribeToRecords(onChange: @escaping @MainActor @Sendable (SupabaseService.RealtimeRecordChange) -> Void) async throws {}
    func subscribeToAgents(onChange: @escaping @MainActor @Sendable (SupabaseService.RealtimeAction) -> Void) async throws {}
    func unsubscribeAll() async {}

    // MARK: - Cache

    func invalidateCache() {}

    // MARK: - Freshness

    func minutesSinceLastFetch(category: RecordCategory? = nil) -> Int? {
        0
    }
}
