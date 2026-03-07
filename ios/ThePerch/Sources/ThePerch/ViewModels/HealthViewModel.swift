import Foundation
import Observation

// MARK: - HealthViewModel

/// Manages the state of the Health section.
/// Loads health records from Supabase and orchestrates HealthKit sync.
@Observable
@MainActor
final class HealthViewModel {
    // MARK: - Properties

    var records: [Record] = []
    var isLoading: Bool = false
    var isSyncing: Bool = false
    var syncError: String?
    var lastSyncDate: Date?
    var syncedCount: Int = 0
    var error: SupabaseServiceError?

    /// Whether HealthKit is available on this device.
    var isHealthKitAvailable: Bool {
        HealthKitService.shared.isAvailable
    }

    // MARK: - Private Properties

    private let supabaseService: SupabaseService
    private let syncService: HealthKitSyncService

    // MARK: - Initialization

    init(
        supabaseService: SupabaseService = .shared,
        syncService: HealthKitSyncService = .shared
    ) {
        self.supabaseService = supabaseService
        self.syncService = syncService
        self.lastSyncDate = syncService.lastSyncDate
    }

    // MARK: - Loading Records

    /// Loads health records from Supabase.
    func loadRecords(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedRecords = try await supabaseService.fetchRecords(
                category: .health,
                limit: 100,
                forceRefresh: forceRefresh
            )
            self.records = loadedRecords
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    // MARK: - HealthKit Sync

    /// Triggers a manual sync with Apple Health.
    func syncWithHealthKit() async {
        isSyncing = true
        syncError = nil

        await syncService.syncAll()

        self.syncedCount = syncService.syncedCount
        self.syncError = syncService.syncError
        self.lastSyncDate = syncService.lastSyncDate
        self.isSyncing = false

        // Reload records to show newly synced data
        if syncService.syncedCount > 0 {
            await loadRecords(forceRefresh: true)
        }
    }

    // MARK: - Computed Properties

    /// Returns all records for a given metric key, sorted chronologically (oldest first for charts).
    func recordsForMetric(_ metric: String) -> [Record] {
        records.filter { $0.asMeasurement()?.metric == metric }
            .sorted {
                guard let m0 = $0.asMeasurement(), let m1 = $1.asMeasurement() else { return false }
                return effectiveDate(for: $0, measurement: m0) < effectiveDate(for: $1, measurement: m1)
            }
    }

    /// Weight records only, sorted newest first.
    var weightRecords: [Record] {
        records.filter { $0.asMeasurement()?.metric == "weight" }
            .sorted {
                guard let m0 = $0.asMeasurement(), let m1 = $1.asMeasurement() else { return false }
                return effectiveDate(for: $0, measurement: m0) > effectiveDate(for: $1, measurement: m1)
            }
    }

    /// All distinct metric keys found in the records.
    var availableMetrics: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in records {
            guard let m = record.asMeasurement() else { continue }
            if !seen.contains(m.metric) {
                seen.insert(m.metric)
                result.append(m.metric)
            }
        }
        return result
    }

    /// Resolves the effective date for a measurement, checking timestamp first,
    /// then context (which Claudinho uses for date strings like "2026-03-06"),
    /// then falling back to record.createdAt.
    private static let contextDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt
    }()

    private func effectiveDate(for record: Record, measurement: MeasurementData) -> Date {
        if let ts = measurement.timestamp { return ts }
        if let ctx = measurement.context,
           let parsed = Self.contextDateFormatter.date(from: ctx) {
            return parsed
        }
        return record.createdAt
    }

    /// The most recent measurement for each metric type.
    var latestByMetric: [String: (Record, MeasurementData)] {
        var latest: [String: (Record, MeasurementData)] = [:]
        for record in records {
            guard let measurement = record.asMeasurement() else { continue }
            let thisDate = effectiveDate(for: record, measurement: measurement)
            if let existing = latest[measurement.metric] {
                let existingDate = effectiveDate(for: existing.0, measurement: existing.1)
                if thisDate > existingDate {
                    latest[measurement.metric] = (record, measurement)
                }
            } else {
                latest[measurement.metric] = (record, measurement)
            }
        }
        return latest
    }

    /// The latest macros record, sorted by the date field in the data payload.
    var latestMacros: (Record, MacrosData)? {
        let macrosRecords = records.compactMap { record -> (Record, MacrosData)? in
            guard let macros = record.asMacros() else { return nil }
            return (record, macros)
        }
        // Sort by the date field in MacrosData (e.g. "2026-03-06"), falling back to createdAt
        return macrosRecords.sorted {
            ($0.1.date ?? "") > ($1.1.date ?? "")
        }.first
    }

    /// Ordered list of chart metrics to display (body comp → sleep → nutrition).
    /// `higherIsBetter`: true means upward trend is green, false means upward trend is red.
    static let chartMetricOrder: [(key: String, title: String, unit: String, emoji: String, higherIsBetter: Bool)] = [
        ("weight", "Weight", "kg", "⚖️", true),
        ("skeletal_muscle", "Skeletal Muscle", "kg", "💪", true),
        ("body_fat_pct", "Body Fat %", "%", "📊", false),
        ("sleep_duration", "Sleep Duration", "hrs", "😴", true),
        ("deep_sleep", "Deep Sleep", "hrs", "🌙", true),
        ("lowest_sleep_hr", "Lowest Sleep HR", "bpm", "❤️", false),
        ("avg_sleep_hrv", "Sleep HRV", "ms", "💓", true),
    ]

    /// Formatted last sync string for display.
    var lastSyncFormatted: String? {
        guard let lastSyncDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSyncDate, relativeTo: Date())
    }
}
