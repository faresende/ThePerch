import Foundation
import Observation

// MARK: - AdminViewModel

/// Manages the state of the Admin section.
/// Loads agents, cost records, and admin records from Supabase.
@Observable
@MainActor
final class AdminViewModel: SectionViewModelProtocol {
    // MARK: - Properties

    var records: [Record] = []
    var agents: [Agent] = []
    var costRecords: [Record] = []
    var isLoading: Bool = false
    var error: SupabaseServiceError?

    // MARK: - Private Properties

    private let supabaseService: SupabaseService

    // MARK: - Initialization

    init(supabaseService: SupabaseService = .shared) {
        self.supabaseService = supabaseService
    }

    // MARK: - Computed Properties

    var activeAgents: [Agent] { agents.filter { $0.isActive } }

    /// Derive gateway running status from the most recent agent heartbeat.
    var gatewayIsRunning: Bool {
        guard let latest = agents.compactMap({ $0.lastHeartbeat }).max() else { return false }
        return Date.now.timeIntervalSince(latest) < 300
    }

    /// Latest heartbeat across all agents.
    var latestHeartbeat: Date? {
        agents.compactMap { $0.lastHeartbeat }.max()
    }

    /// Cron job records from admin category, sorted by next run time.
    var cronRecords: [Record] {
        records.filter { $0.asCronJob() != nil }
            .sorted { r1, r2 in
                let d1 = r1.asCronJob()?.nextRunAt ?? .distantFuture
                let d2 = r2.asCronJob()?.nextRunAt ?? .distantFuture
                return d1 < d2
            }
    }

    /// Gateway status record (if available).
    var gatewayStatus: GatewayStatusData? {
        records.compactMap { $0.asGatewayStatus() }.first
    }

    // MARK: - Loading Data

    func loadRecords(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let fetchedAgents = supabaseService.fetchAgents(forceRefresh: forceRefresh)
            async let fetchedCosts = supabaseService.fetchRecords(
                category: .admin,
                type: .costSummary,
                limit: 10,
                forceRefresh: forceRefresh
            )
            async let fetchedAdmin = supabaseService.fetchRecords(
                category: .admin,
                limit: 50,
                forceRefresh: forceRefresh
            )

            agents = try await fetchedAgents
            costRecords = try await fetchedCosts
            records = try await fetchedAdmin
            DataFreshnessTracker.shared.recordFetch(for: "admin")
        } catch let err as SupabaseServiceError {
            error = err
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    func refresh() async {
        await loadRecords(forceRefresh: true)
    }

    // MARK: - Helpers

    func statusDataForAgent(_ agent: Agent) -> StatusData {
        let state: String
        if agent.isActive && agent.isHealthy {
            state = "active"
        } else if agent.isActive {
            state = "idle"
        } else {
            state = "error"
        }

        let uptimeHours: Double
        if agent.lastHeartbeat != nil {
            uptimeHours = Date.now.timeIntervalSince(agent.createdAt) / 3600
        } else {
            uptimeHours = 0
        }

        return StatusData(
            state: state,
            uptimeHours: uptimeHours,
            lastActivity: agent.lastHeartbeat,
            currentTask: nil
        )
    }

    func agentEmojiForId(_ agentId: String) -> String {
        if let agent = agents.first(where: { $0.id == agentId }), let emoji = agent.emoji {
            return emoji
        }
        switch agentId {
        case "claudinho": return "🤖"
        case "biochecha": return "💊"
        case "entregas": return "📦"
        case "calendario": return "📅"
        case "legal": return "⚖️"
        case "archie": return "📚"
        default: return "⚙️"
        }
    }

    func agentNameForId(_ agentId: String) -> String {
        if let agent = agents.first(where: { $0.id == agentId }) {
            return agent.displayName
        }
        return agentId.capitalized
    }
}
