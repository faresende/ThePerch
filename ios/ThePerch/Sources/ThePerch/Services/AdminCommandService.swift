import Foundation

// MARK: - AdminCommandService

/// Service for sending remote admin commands (restart gateway, doctor fix)
/// via the Supabase command queue. Commands are inserted as dashboard_records
/// with category=admin, type=command, and polled for status updates.
@MainActor
final class AdminCommandService {
    static let shared = AdminCommandService()

    private let supabaseService = SupabaseService.shared
    private let userId = AppConfig.defaultUserID
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
            print("[AdminCommandService] Failed to fetch command status: \(error)")
            return nil
        }
    }
}

// MARK: - Errors

enum AdminCommandError: LocalizedError {
    case rateLimited(remainingSeconds: Int)
    case commandNotFound

    var errorDescription: String? {
        switch self {
        case .rateLimited(let seconds):
            return "Rate limited. Please wait \(seconds) seconds before sending another command."
        case .commandNotFound:
            return "Command record not found after insertion."
        }
    }
}
