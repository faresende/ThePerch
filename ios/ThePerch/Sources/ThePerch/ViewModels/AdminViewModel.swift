import Foundation
import Observation
import SwiftUI

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

    // MARK: - Remote Command Properties

    private let commandService = AdminCommandService.shared

    /// Current command execution state per command type.
    var restartState: CommandExecutionState = .idle
    var doctorFixState: CommandExecutionState = .idle

    /// Recent command history.
    var recentCommands: [Record] = []

    /// Active polling task.
    private var pollingTask: Task<Void, Never>?

    enum CommandExecutionState: Equatable {
        case idle
        case confirming
        case executing(String) // message
        case completed(String) // result message
        case failed(String)    // error message
    }

    // MARK: - Updating Data (fed from DashboardViewModel)

    /// Called when DashboardViewModel.adminRecords changes.
    func updateRecords(_ newRecords: [Record]) {
        records = newRecords
        costRecords = newRecords.filter { $0.type == .costSummary }
        recentCommands = newRecords
            .filter { $0.type == .command }
            .sorted { $0.createdAt > $1.createdAt }
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

    // MARK: - Remote Command Execution

    var canSendCommand: Bool { commandService.canSendCommand }
    var rateLimitRemainingSeconds: Int { commandService.rateLimitRemainingSeconds }

    /// Sends a command and polls for status updates.
    func executeCommand(_ command: AdminCommandData.AdminCommand) async {
        let isRestart = command == .restartGateway

        // Update state
        if isRestart {
            restartState = .executing("Sending command...")
        } else {
            doctorFixState = .executing("Sending command...")
        }

        do {
            let recordId = try await commandService.sendCommand(command)

            if isRestart {
                restartState = .executing("Restarting...")
            } else {
                doctorFixState = .executing("Running diagnostics...")
            }

            // Poll for status updates
            pollingTask?.cancel()
            pollingTask = Task { [weak self] in
                guard let self else { return }
                for await status in commandService.observeCommand(id: recordId) {
                    guard !Task.isCancelled else { break }
                    await self.handleStatusUpdate(status, command: command)
                }
            }
        } catch {
            let message = error.localizedDescription
            if isRestart {
                restartState = .failed(message)
            } else {
                doctorFixState = .failed(message)
            }
            PerchHaptics.error()
        }
    }

    private func handleStatusUpdate(_ data: AdminCommandData, command: AdminCommandData.AdminCommand) {
        let isRestart = command == .restartGateway

        switch data.status {
        case .pending:
            if isRestart {
                restartState = .executing("Pending...")
            } else {
                doctorFixState = .executing("Pending...")
            }
        case .executing:
            if isRestart {
                restartState = .executing("Restarting gateway...")
            } else {
                doctorFixState = .executing("Running diagnostics...")
            }
        case .completed:
            let message = data.result?.message ?? "Done"
            if isRestart {
                restartState = .completed(message)
            } else {
                doctorFixState = .completed(message)
            }
            PerchHaptics.success()
            // Reset after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if isRestart {
                    if case .completed = self.restartState { self.restartState = .idle }
                } else {
                    if case .completed = self.doctorFixState { self.doctorFixState = .idle }
                }
            }
        case .failed:
            let message = data.result?.message ?? "Command failed"
            if isRestart {
                restartState = .failed(message)
            } else {
                doctorFixState = .failed(message)
            }
            PerchHaptics.error()
            // Reset after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if isRestart {
                    if case .failed = self.restartState { self.restartState = .idle }
                } else {
                    if case .failed = self.doctorFixState { self.doctorFixState = .idle }
                }
            }
        }
    }

    /// Loads recent command history.
    func loadRecentCommands() async {
        do {
            let commands = try await commandService.getRecentCommands(limit: 5)
            recentCommands = commands
        } catch {
            print("[AdminViewModel] Failed to load recent commands: \(error)")
        }
    }

    // MARK: - Gateway Freshness

    /// Returns a freshness descriptor for the gateway status based on the most recent status record's updatedAt.
    var gatewayFreshness: GatewayFreshness {
        // Find the gateway status record
        guard let statusRecord = records.first(where: { $0.asGatewayStatus() != nil }) else {
            return .offline
        }

        let elapsed = Date.now.timeIntervalSince(statusRecord.updatedAt)

        if elapsed > 86400 { return .offline }          // >24 hours
        if elapsed > 3600 { return .possiblyOffline(elapsed) } // >1 hour
        if elapsed > 300 { return .stale(elapsed) }     // >5 minutes
        return .fresh(elapsed)                           // <5 minutes
    }

    enum GatewayFreshness {
        case fresh(TimeInterval)
        case stale(TimeInterval)
        case possiblyOffline(TimeInterval)
        case offline

        var label: String {
            switch self {
            case .fresh(let interval):
                let minutes = Int(interval / 60)
                return minutes < 1 ? "Online · Updated just now" : "Online · Updated \(minutes)m ago"
            case .stale(let interval):
                let minutes = Int(interval / 60)
                return "Online · Updated \(minutes)m ago"
            case .possiblyOffline(let interval):
                let hours = Int(interval / 3600)
                return "Possibly Offline · Last seen \(hours)h ago"
            case .offline:
                return "Offline"
            }
        }

        var color: Color {
            switch self {
            case .fresh: return PerchTheme.success
            case .stale: return PerchTheme.warning
            case .possiblyOffline: return PerchTheme.error
            case .offline: return PerchTheme.error
            }
        }
    }
}
