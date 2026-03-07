import Foundation
import Combine
import Supabase
import Realtime

// MARK: - Error Types

/// Errors that can occur during Supabase operations.
enum SupabaseServiceError: LocalizedError {
    case clientNotInitialized
    case authError(String)
    case queryError(String)
    case decodingError(String)
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
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - SupabaseService

/// A singleton service for managing Supabase interactions.
/// Connects to the real Supabase backend, with mock data fallback.
@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    // MARK: - Published Properties

    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: SupabaseServiceError?

    // MARK: - Private Properties

    /// Toggle to fall back to mock data if Supabase is unreachable or empty.
    /// Set to false once your Supabase tables have real data.
    private var useMockData = false

    /// The Supabase client instance.
    private let client: SupabaseClient

    /// Custom JSON decoder for Supabase responses (handles snake_case + ISO8601 dates).
    private let snakeCaseDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Initialization

    private init() {
        let config = AppConfig.shared
        self.client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.supabaseAnonKey
        )
    }

    // MARK: - Authentication Methods

    /// Signs in a user with email and password.
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            self.isAuthenticated = true
            self.error = nil
            return
        }

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

        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            self.isAuthenticated = true
            self.error = nil
            return
        }

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
        if useMockData {
            self.isAuthenticated = false
            self.error = nil
            return
        }

        do {
            try await client.auth.signOut()
            self.isAuthenticated = false
            self.error = nil
        } catch {
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Checks for an existing session and restores it.
    func restoreSession() async {
        if useMockData {
            self.isAuthenticated = true
            return
        }

        do {
            let session = try await client.auth.session
            self.isAuthenticated = true
            print("[SupabaseService] Session restored for user: \(session.user.id)")
        } catch {
            self.isAuthenticated = false
            print("[SupabaseService] No active session: \(error.localizedDescription)")
        }
    }

    // MARK: - Query Methods

    /// Fetches records from the database, with optional filtering.
    func fetchRecords(
        category: RecordCategory? = nil,
        type: RecordType? = nil,
        limit: Int = 100
    ) async throws -> [Record] {
        if useMockData {
            try await Task.sleep(nanoseconds: 300_000_000)
            var records = MockData.allRecords
            if let category { records = records.filter { $0.category == category } }
            if let type { records = records.filter { $0.type == type } }
            return Array(records.prefix(limit))
        }

        do {
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

            let rawJSON = String(data: result.data, encoding: .utf8) ?? "nil"
            print("[SupabaseService] fetchRecords raw (\(category?.rawValue ?? "all")): \(rawJSON.prefix(500))")

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let records = try decoder.decode([Record].self, from: result.data)
            print("[SupabaseService] fetchRecords decoded \(records.count) records")
            return records
        } catch {
            print("[SupabaseService] fetchRecords error: \(error)")
            // Fall back to mock data on failure
            useMockData = true
            return try await fetchRecords(category: category, type: type, limit: limit)
        }
    }

    /// Fetches all active agents.
    func fetchAgents() async throws -> [Agent] {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            return MockData.agents
        }

        do {
            let response: [Agent] = try await client.from("agents")
                .select()
                .eq("is_active", value: true)
                .execute()
                .value
            return response
        } catch {
            print("[SupabaseService] fetchAgents error: \(error)")
            useMockData = true
            return try await fetchAgents()
        }
    }

    /// Fetches token usage statistics.
    func fetchTokenUsage(agentId: String? = nil, days: Int = 30) async throws -> [TokenUsage] {
        if useMockData {
            return []
        }

        do {
            var query = client.from("token_usage").select()

            if let agentId {
                query = query.eq("agent_id", value: agentId)
            }

            let response: [TokenUsage] = try await query
                .order("date", ascending: false)
                .limit(days)
                .execute()
                .value
            return response
        } catch {
            print("[SupabaseService] fetchTokenUsage error: \(error)")
            return []
        }
    }

    /// Fetches all sections for the current user.
    func fetchSections() async throws -> [Section] {
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            print("[SupabaseService] Using mock sections")
            return MockData.sections
        }

        do {
            let result = try await client.from("sections")
                .select()
                .order("sort_order", ascending: true)
                .execute()

            // Debug: print the raw JSON response
            let rawJSON = String(data: result.data, encoding: .utf8) ?? "nil"
            print("[SupabaseService] fetchSections raw response: \(rawJSON)")

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let sections = try decoder.decode([Section].self, from: result.data)
            print("[SupabaseService] fetchSections decoded \(sections.count) sections")

            // If Supabase returned empty (e.g., RLS blocking), fall back to mock
            if sections.isEmpty {
                print("[SupabaseService] Sections empty, falling back to mock")
                useMockData = true
                return try await fetchSections()
            }
            return sections
        } catch {
            print("[SupabaseService] fetchSections error: \(error)")
            useMockData = true
            return try await fetchSections()
        }
    }

    /// Fetches all home widget configurations for the current user.
    func fetchHomeWidgets() async throws -> [HomeWidget] {
        if useMockData {
            return []
        }

        do {
            let response: [HomeWidget] = try await client.from("home_widgets")
                .select()
                .order("position", ascending: true)
                .execute()
                .value
            return response
        } catch {
            print("[SupabaseService] fetchHomeWidgets error: \(error)")
            return []
        }
    }

    // MARK: - Mutation Methods

    /// Updates the pinned state of a record.
    func updateRecordPin(id: UUID, pinned: Bool) async throws {
        if useMockData { return }

        struct PinUpdate: Encodable { let pinned: Bool }

        do {
            try await client.from("dashboard_records")
                .update(PinUpdate(pinned: pinned))
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            throw SupabaseServiceError.queryError(error.localizedDescription)
        }
    }

    /// Updates the sort order of sections.
    func updateSectionOrder(sections: [Section]) async throws {
        if useMockData { return }

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
    }

    /// Updates home widget configurations.
    func updateHomeWidgets(widgets: [HomeWidget]) async throws {
        if useMockData { return }
        // TODO: Implement batch widget update
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
        if useMockData {
            print("[SupabaseService] Mock mode: would insert \(title) record")
            return
        }

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
            print("[SupabaseService] Inserted record: \(title)")
        } catch {
            print("[SupabaseService] insertRecord error: \(error)")
            throw SupabaseServiceError.queryError(error.localizedDescription)
        }
    }

    // MARK: - Realtime Subscriptions

    /// Subscribes to realtime record changes.
    func subscribeToRecords(onChange: @escaping @Sendable (Any) -> Void) async throws {
        if useMockData { return }
        // TODO: Implement Supabase Realtime channel subscription
    }

    /// Subscribes to realtime agent status changes.
    func subscribeToAgents(onChange: @escaping @Sendable (Any) -> Void) async throws {
        if useMockData { return }
        // TODO: Implement Supabase Realtime channel subscription
    }
}

