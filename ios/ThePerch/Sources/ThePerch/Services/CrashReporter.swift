import Foundation

/// Simple file-based crash reporter.
/// Writes uncaught exception info to the app's documents directory.
/// On next launch, checks for crash files and can report them.
@MainActor
final class CrashReporter {
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
        // Compute the directory URL synchronously — cheap, no I/O.
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.crashesDirectory = documentsDir.appendingPathComponent("crashes", isDirectory: true)
        // Filesystem work (createDirectory + scanning previous reports)
        // is deferred to `loadPendingReportsIfNeeded()` which the app
        // calls from a `.task` after first frame paints. Keeping it
        // out of `init()` shaves ~10–30ms off the synchronous cold-
        // start critical path.
    }

    /// Idempotent: creates the crashes directory if needed and reads any
    /// pending crash reports off-thread. Call once after the first frame
    /// has painted (e.g. from ThePerchApp's `.task`).
    func loadPendingReportsIfNeeded() async {
        // Hop off MainActor for the FS work.
        let dir = crashesDirectory
        let reports: [CrashReport] = await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return CrashReporter.scanReports(in: dir)
        }.value
        self.pendingCrashReports = reports
        self.hasPendingCrashReports = !reports.isEmpty
    }

    /// Pure scan helper — runs off-MainActor.
    nonisolated private static func scanReports(in dir: URL) -> [CrashReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let crashFiles = files.filter { $0.pathExtension == "txt" }
        return crashFiles.compactMap { fileURL in
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let creationDate = attrs[.creationDate] as? Date else { return nil }

            let lines = content.components(separatedBy: "\n")
            let name = lines.first(where: { $0.hasPrefix("Crash:") })?
                .replacingOccurrences(of: "Crash: ", with: "") ?? "Unknown"
            let reason = lines.first(where: { $0.hasPrefix("Reason:") })?
                .replacingOccurrences(of: "Reason: ", with: "") ?? "Unknown"
            let stackStart = lines.firstIndex(of: "Stack Trace:") ?? lines.count
            let stackTrace = stackStart < lines.count
                ? lines[(stackStart + 1)...].joined(separator: "\n")
                : ""
            return CrashReport(
                id: UUID(),
                name: name,
                reason: reason,
                stackTrace: stackTrace,
                timestamp: creationDate,
                fileURL: fileURL
            )
        }
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
            Date: \(PerchFormatters.iso8601.string(from: Date()))
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
