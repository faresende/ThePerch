import Foundation
import PostgREST
import Supabase

// MARK: - AdminCommandService

/// Service for sending remote admin commands (restart gateway, doctor fix)
/// via the Supabase command queue. Commands are inserted as dashboard_records
/// with category=admin, type=command, and polled for status updates.
@MainActor
final class AdminCommandService {
    static let shared = AdminCommandService()

    private let supabaseService = SupabaseService.shared
    private let agentId = "theperch_ios"

    /// Rate limiting: minimum interval between commands (2 minutes).
    private let rateLimitInterval: TimeInterval = 120
    private var lastCommandTime: Date?

    private init() {}

    // MARK: - Rate Limiting

    /// Returns true if a command can be sent (respecting rate limit).
    var canSendCommand: Bool {
        guard let last = lastCommandTime else { return true }
        return Date.now.timeIntervalSince(last) >= rateLimitInterval
    }

    /// Seconds remaining until rate limit expires.
    var rateLimitRemainingSeconds: Int {
        guard let last = lastCommandTime else { return 0 }
        let elapsed = Date.now.timeIntervalSince(last)
        let remaining = rateLimitInterval - elapsed
        return max(0, Int(remaining))
    }

    // MARK: - Send Command

    /// Sends an admin command by inserting a new record into dashboard_records.
    /// Returns the record ID for polling.
    /// - Throws: If rate limited or insert fails.
    func sendCommand(_ command: AdminCommandData.AdminCommand) async throws -> UUID {
        guard canSendCommand else {
            throw AdminCommandError.rateLimited(remainingSeconds: rateLimitRemainingSeconds)
        }
        guard let userId = supabaseService.currentUserId.flatMap(UUID.init(uuidString:)) else {
            throw AdminCommandError.notAuthenticated
        }

        let commandData: [String: JSONValue] = [
            "command": .string(command.rawValue),
            "status": .string(AdminCommandData.CommandStatus.pending.rawValue),
            "created_at": .string(PerchFormatters.iso8601.string(from: Date.now))
        ]

        try await supabaseService.insertRecord(
            agentId: agentId,
            userId: userId,
            type: .command,
            category: .admin,
            title: command.displayName,
            data: commandData,
            displayHint: .statusList
        )

        lastCommandTime = Date.now

        // Fetch the most recent command record to get its ID
        let records = try await supabaseService.fetchRecords(
            category: .admin,
            type: .command,
            limit: 1,
            forceRefresh: true
        )

        guard let record = records.first else {
            throw AdminCommandError.commandNotFound
        }

        return record.id
    }

    // MARK: - Observe Command

    /// Polls for command status changes every 2 seconds, up to 60 seconds.
    /// Yields status updates via the returned AsyncStream.
    func observeCommand(id: UUID) -> AsyncStream<AdminCommandData> {
        AsyncStream { continuation in
            let task = Task {
                let maxAttempts = 30 // 30 x 2s = 60s
                for _ in 0..<maxAttempts {
                    guard !Task.isCancelled else { break }

                    if let commandData = await fetchCommandStatus(id: id) {
                        continuation.yield(commandData)

                        if commandData.status == .completed || commandData.status == .failed {
                            break
                        }
                    }

                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Fetch Recent Commands

    /// Fetches recent admin command records.
    func getRecentCommands(limit: Int = 5) async throws -> [Record] {
        try await supabaseService.fetchRecords(
            category: .admin,
            type: .command,
            limit: limit,
            forceRefresh: true
        )
    }

    // MARK: - Private

    private func fetchCommandStatus(id: UUID) async -> AdminCommandData? {
        do {
            let records = try await supabaseService.fetchRecords(
                category: .admin,
                type: .command,
                limit: 10,
                forceRefresh: true
            )
            return records.first(where: { $0.id == id })?.asAdminCommand()
        } catch {
            #if DEBUG
            print("[AdminCommandService] Failed to fetch command status: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Agent Runs (observability)

    private let agentRunsDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Fetch the most recent agent_runs rows (across all agents). Powers the
    /// observability surface in DebugAdminView — one row per pipeline firing,
    /// ok/error/partial/timeout status, summary + optional error detail.
    ///
    /// The server-side `agent_runs_latest` view pre-dedupes to one row per
    /// (agent_id, run_type). This function reads from the raw table so the
    /// admin view can show history, not just the latest.
    func fetchRecentAgentRuns(limit: Int = 100) async throws -> [AgentRun] {
        let result = try await supabaseService.databaseClient
            .from("agent_runs")
            .select()
            .order("started_at", ascending: false)
            .limit(limit)
            .execute()

        let rawArray = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] ?? []
        var runs: [AgentRun] = []
        runs.reserveCapacity(rawArray.count)
        for item in rawArray {
            do {
                let data = try JSONSerialization.data(withJSONObject: item)
                runs.append(try agentRunsDecoder.decode(AgentRun.self, from: data))
            } catch {
                #if DEBUG
                print("[AdminCommandService] Dropping malformed agent_run: \(error)")
                #endif
            }
        }
        return runs
    }
}

// MARK: - Errors

enum AdminCommandError: LocalizedError {
    case rateLimited(remainingSeconds: Int)
    case commandNotFound
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .rateLimited(let seconds):
            return "Rate limited. Please wait \(seconds) seconds before sending another command."
        case .commandNotFound:
            return "Command record not found after insertion."
        case .notAuthenticated:
            return "You must be signed in to send admin commands."
        }
    }
}
