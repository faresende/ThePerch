import Foundation

/// Simple file-based crash reporter.
/// Writes uncaught exception info to the app's documents directory.
/// On next launch, checks for crash files and can report them.
final class CrashReporter: @unchecked Sendable {
    static let shared = CrashReporter()

    /// Whether there are pending crash reports from a previous session.
    private(set) var hasPendingCrashReports: Bool = false
    private(set) var pendingCrashReports: [CrashReport] = []

    struct CrashReport: Identifiable {
        let id: UUID
        let name: String
        let reason: String
        let stackTrace: String
        let timestamp: Date
        let fileURL: URL
    }

    private let crashesDirectory: URL

    private init() {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.crashesDirectory = documentsDir.appendingPathComponent("crashes", isDirectory: true)

        // Create crashes directory if needed
        try? FileManager.default.createDirectory(at: crashesDirectory, withIntermediateDirectories: true)

        // Check for pending reports
        loadPendingReports()
    }

    // MARK: - Setup

    /// Installs the uncaught exception handler. Call from App init.
    nonisolated func installHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let name = exception.name.rawValue
            let reason = exception.reason ?? "Unknown reason"
            let symbols = exception.callStackSymbols.joined(separator: "\n")

            let crashInfo = """
            Crash: \(name)
            Reason: \(reason)
            Date: \(ISO8601DateFormatter().string(from: Date()))
            Stack Trace:
            \(symbols)
            """

            // Write synchronously since the app is about to terminate
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let crashesDir = documentsDir.appendingPathComponent("crashes", isDirectory: true)
            try? FileManager.default.createDirectory(at: crashesDir, withIntermediateDirectories: true)

            let fileName = "crash_\(UUID().uuidString).txt"
            let fileURL = crashesDir.appendingPathComponent(fileName)
            try? crashInfo.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Pending Reports

    private func loadPendingReports() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: crashesDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let crashFiles = files.filter { $0.pathExtension == "txt" }
        pendingCrashReports = crashFiles.compactMap { fileURL in
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let creationDate = attrs[.creationDate] as? Date else { return nil }

            let lines = content.components(separatedBy: "\n")
            let name = lines.first(where: { $0.hasPrefix("Crash:") })?.replacingOccurrences(of: "Crash: ", with: "") ?? "Unknown"
            let reason = lines.first(where: { $0.hasPrefix("Reason:") })?.replacingOccurrences(of: "Reason: ", with: "") ?? "Unknown"

            return CrashReport(
                id: UUID(),
                name: name,
                reason: reason,
                stackTrace: content,
                timestamp: creationDate,
                fileURL: fileURL
            )
        }
        hasPendingCrashReports = !pendingCrashReports.isEmpty
    }

    /// Deletes all pending crash reports after they've been handled.
    func clearCrashReports() {
        for report in pendingCrashReports {
            try? FileManager.default.removeItem(at: report.fileURL)
        }
        pendingCrashReports = []
        hasPendingCrashReports = false
    }

    /// Returns a summary string of pending crashes for display.
    func crashSummary() -> String? {
        guard let first = pendingCrashReports.first else { return nil }
        let count = pendingCrashReports.count
        if count == 1 {
            return "Previous crash: \(first.reason)"
        }
        return "\(count) crashes detected from previous sessions"
    }
}
