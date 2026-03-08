import Foundation
import Observation

// MARK: - AdminViewModel

/// Manages the state of the Admin section.
/// Records are fed from DashboardViewModel (single-fetch architecture).
/// Agents are fetched separately via DashboardViewModel.loadAgents().
@Observable
@MainActor
final class AdminViewModel {
    // MARK: - Properties

    var records: [Record] = []
    var agents: [Agent] = []
    var costRecords: [Record] = []

    // MARK: - Updating Data (fed from DashboardViewModel)

    /// Called when DashboardViewModel.adminRecords changes.
    func updateRecords(_ newRecords: [Record]) {
        records = newRecords
        costRecords = newRecords.filter { $0.type == .costSummary }
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
        records
            .compactMap { record -> (Record, CronJobData)? in
                guard let cron = record.asCronJob() else { return nil }
                return (record, cron)
            }
            .sorted { $0.1.nextRunAt ?? .distantFuture < $1.1.nextRunAt ?? .distantFuture }
            .map(\.0)
    }

    /// Gateway status record (if available).
    var gatewayStatus: GatewayStatusData? {
        records.compactMap { $0.asGatewayStatus() }.first
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
