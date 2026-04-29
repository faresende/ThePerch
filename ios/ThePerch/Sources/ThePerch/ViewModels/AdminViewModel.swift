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
        return AgentIdentity.emoji(for: agentId)
    }

    func agentNameForId(_ agentId: String) -> String {
        if let agent = agents.first(where: { $0.id == agentId }) {
            return agent.displayName
        }
        return AgentIdentity.name(for: agentId)
    }

    func displayNameForAgent(_ agent: Agent) -> String {
        let duplicateCount = agents.filter {
            $0.displayName.caseInsensitiveCompare(agent.displayName) == .orderedSame
        }.count

        guard duplicateCount > 1 else { return agent.displayName }
        return "\(agent.displayName) (\(agent.disambiguationLabel))"
    }

    // MARK: - Remote Command Execution

    var canSendCommand: Bool { commandService.canSendCommand }
    var rateLimitRemainingSeconds: Int { commandService.rateLimitRemainingSeconds }

    /// Sends a command and polls for status updates.
    func executeCommand(_ command: AdminCommandData.AdminCommand) async {
        updateCommandState(command, to: .executing("Sending command..."))

        do {
            let recordId = try await commandService.sendCommand(command)

            updateCommandState(
                command,
                to: .executing(command == .restartGateway ? "Restarting..." : "Running diagnostics...")
            )

            // Poll for status updates
            pollingTask?.cancel()
            pollingTask = Task { [weak self] in
                guard let self else { return }
                for await status in self.commandService.observeCommand(id: recordId) {
                    guard !Task.isCancelled else { break }
                    self.handleStatusUpdate(status, command: command)
                }
            }
        } catch {
            updateCommandState(command, to: .failed(error.localizedDescription))
            scheduleReset(for: command)
            PerchHaptics.error()
        }
    }

    private func handleStatusUpdate(_ data: AdminCommandData, command: AdminCommandData.AdminCommand) {
        switch data.status {
        case .pending:
            updateCommandState(command, to: .executing("Pending..."))
        case .executing:
            updateCommandState(
                command,
                to: .executing(command == .restartGateway ? "Restarting gateway..." : "Running diagnostics...")
            )
        case .completed:
            updateCommandState(command, to: .completed("Done"))
            pollingTask?.cancel()
            pollingTask = nil
            PerchHaptics.success()
            scheduleReset(for: command)
        case .failed:
            let message = data.result?.message ?? "Command failed"
            updateCommandState(command, to: .failed(message))
            pollingTask?.cancel()
            pollingTask = nil
            PerchHaptics.error()
            scheduleReset(for: command)
        }
    }

    private func updateCommandState(
        _ command: AdminCommandData.AdminCommand,
        to newState: CommandExecutionState
    ) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch command {
            case .restartGateway:
                restartState = newState
            case .doctorFix:
                doctorFixState = newState
            case .statusCheck:
                break
            }
        }
    }

    private func scheduleReset(for command: AdminCommandData.AdminCommand) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }

            switch command {
            case .restartGateway:
                guard case .completed = self.restartState else {
                    guard case .failed = self.restartState else { return }
                    self.updateCommandState(command, to: .idle)
                    return
                }
                self.updateCommandState(command, to: .idle)
            case .doctorFix:
                guard case .completed = self.doctorFixState else {
                    guard case .failed = self.doctorFixState else { return }
                    self.updateCommandState(command, to: .idle)
                    return
                }
                self.updateCommandState(command, to: .idle)
            case .statusCheck:
                return
            }
        }
    }

    /// Loads recent command history.
    func loadRecentCommands() async {
        do {
            let commands = try await commandService.getRecentCommands(limit: 5)
            recentCommands = commands
        } catch {
            #if DEBUG
            print("[AdminViewModel] Failed to load recent commands: \(error)")
            #endif
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
