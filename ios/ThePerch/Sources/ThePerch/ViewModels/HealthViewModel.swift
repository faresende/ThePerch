import Foundation
import Observation

// MARK: - HealthViewModel

/// Manages the state of the Health section.
/// Records are fed from DashboardViewModel (single-fetch architecture).
/// Handles HealthKit sync and computed metric properties.
@Observable
@MainActor
final class HealthViewModel {
    // MARK: - Properties

    var records: [Record] = [] {
        didSet { recomputeMetricCaches() }
    }
    var isSyncing: Bool = false
    var syncError: String?
    var lastSyncDate: Date?
    var syncedCount: Int = 0
    var error: SupabaseServiceError?
    var isSavingToHealth: Bool = false
    var healthExportError: String?
    var healthExportSuccess: String?

    /// Whether HealthKit is available on this device.
    var isHealthKitAvailable: Bool {
        healthKitService.isAvailable
    }

    // MARK: - Private Properties

    private let syncService: HealthKitSyncService
    private let healthKitService: HealthKitServiceProtocol
    private let calendar: Calendar
    private let now: () -> Date

    let syntheticNutritionRecordID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func isSyntheticNutritionRecord(_ record: Record) -> Bool {
        record.id == syntheticNutritionRecordID
    }

    // MARK: - Initialization

    init(
        syncService: HealthKitSyncService? = nil,
        healthKitService: HealthKitServiceProtocol? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        let syncService = syncService ?? .shared
        self.syncService = syncService
        self.healthKitService = healthKitService ?? HealthKitService.shared
        self.calendar = calendar
        self.now = now
        self.lastSyncDate = syncService.lastSyncDate
    }

    /// Clears any error messages.
    func clearError() {
        self.error = nil
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
    }

    /// Saves the latest real daily calories measurement into Apple Health.
    func saveDailyCaloriesToHealth() async {
        healthExportError = nil
        healthExportSuccess = nil

        guard let (_, measurement) = latestDailyCalories else {
            healthExportError = "No real daily calories available to save"
            return
        }

        isSavingToHealth = true
        defer { isSavingToHealth = false }

        do {
            try await healthKitService.saveDailyCalories(measurement)
            healthExportSuccess = "Saved daily calories to Apple Health"
        } catch {
            healthExportError = error.localizedDescription
        }
    }

    // MARK: - Computed Properties

    /// Cache invalidated on every `records` mutation. Body reads of
    /// `latestByMetric` (4×) and `recordsForMetric` (7×) used to do a
    /// full O(n) pass over 1000+ records every render. Now: one pass
    /// per records-set, O(1) lookups thereafter.
    private var _latestByMetric: [String: (Record, MeasurementData)] = [:]
    private var _recordsByMetric: [String: [Record]] = [:]

    private func recomputeMetricCaches() {
        var latest: [String: (Record, MeasurementData, Date)] = [:]
        var byMetric: [String: [Record]] = [:]

        for record in records {
            guard let measurement = record.asMeasurement() else { continue }
            byMetric[measurement.metric, default: []].append(record)

            let thisDate = effectiveDate(for: record, measurement: measurement)
            if let existing = latest[measurement.metric] {
                if thisDate > existing.2 {
                    latest[measurement.metric] = (record, measurement, thisDate)
                } else if thisDate == existing.2, record.updatedAt > existing.0.updatedAt {
                    latest[measurement.metric] = (record, measurement, thisDate)
                }
            } else {
                latest[measurement.metric] = (record, measurement, thisDate)
            }
        }

        // Sort each metric's records oldest-first for charts.
        for (metric, recs) in byMetric {
            byMetric[metric] = recs.sorted {
                guard let m0 = $0.asMeasurement(), let m1 = $1.asMeasurement() else { return false }
                return effectiveDate(for: $0, measurement: m0) < effectiveDate(for: $1, measurement: m1)
            }
        }

        _latestByMetric = latest.mapValues { ($0.0, $0.1) }
        _recordsByMetric = byMetric
    }

    /// Returns all records for a given metric key, sorted chronologically (oldest first for charts).
    func recordsForMetric(_ metric: String) -> [Record] {
        _recordsByMetric[metric] ?? []
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
    private func effectiveDate(for record: Record, measurement: MeasurementData) -> Date {
        if let ts = measurement.timestamp { return ts }
        if let ctx = measurement.context,
           let parsed = PerchFormatters.isoDate.date(from: ctx) {
            return parsed
        }
        return record.createdAt
    }

    /// The most recent measurement for each metric type. Reads from the
    /// cached dictionary populated by `recomputeMetricCaches()`.
    var latestByMetric: [String: (Record, MeasurementData)] { _latestByMetric }

    /// The daily calories record for the current nutrition day.
    /// Before 2am, falls back to yesterday's final tally.
    /// After 2am, only today's data is shown.
    var latestDailyCalories: (Record, MeasurementData)? {
        let caloriesRecords = records.compactMap { record -> (Record, MeasurementData)? in
            guard let measurement = record.asMeasurement(), measurement.metric == "daily_calories" else { return nil }
            return (record, measurement)
        }

        let nutritionDay = currentNutritionDay()

        let todayContextMatches = caloriesRecords
            .filter { $0.1.context == nutritionDay.today }
            .sorted { $0.0.updatedAt > $1.0.updatedAt }
        if let match = todayContextMatches.first {
            return match
        }

        let todayTimestampMatches = caloriesRecords
            .filter { sample in
                guard let timestamp = sample.1.timestamp else { return false }
                return calendar.isDate(timestamp, inSameDayAs: now())
            }
            .sorted {
                ($0.1.timestamp ?? $0.0.updatedAt) > ($1.1.timestamp ?? $1.0.updatedAt)
            }
        if let match = todayTimestampMatches.first {
            return match
        }

        guard nutritionDay.isLateNight else { return nil }

        return caloriesRecords
            .filter { $0.1.context == nutritionDay.yesterday }
            .sorted { $0.0.updatedAt > $1.0.updatedAt }
            .first
    }

    /// The macros record for the current nutrition day.
    /// Before 2am, falls back to yesterday's final tally.
    /// After 2am, only today's data is shown.
    var latestMacros: (Record, MacrosData)? {
        let nutritionDay = currentNutritionDay()
        let macrosRecords = records.compactMap { record -> (Record, MacrosData)? in
            guard let macros = record.asMacros() else { return nil }
            return (record, macros)
        }

        let todayMatches = macrosRecords
            .filter { $0.1.date == nutritionDay.today }
            .sorted { $0.0.updatedAt > $1.0.updatedAt }
        if let match = todayMatches.first {
            return match
        }

        guard nutritionDay.isLateNight else { return nil }

        return macrosRecords
            .filter { $0.1.date == nutritionDay.yesterday }
            .sorted { $0.0.updatedAt > $1.0.updatedAt }
            .first
    }

    /// The calories card content to display in Health.
    /// After 2am with no data for today, returns a synthetic zero-state.
    var displayedDailyCalories: (Record, MeasurementData)? {
        if let latestDailyCalories {
            return latestDailyCalories
        }

        let nutritionDay = currentNutritionDay()
        guard nutritionDay.isLateNight == false else {
            return nil
        }

        return (syntheticNutritionRecord(for: nutritionDay.today), MeasurementData(
            metric: "daily_calories",
            value: 0,
            unit: "kcal",
            context: nutritionDay.today,
            timestamp: nil,
            target: 3400,
            displayValue: nil
        ))
    }

    /// The macros card content to display in Health.
    /// After 2am with no data for today, returns a synthetic zero-state.
    var displayedMacros: (Record, MacrosData)? {
        if let latestMacros {
            return latestMacros
        }

        let nutritionDay = currentNutritionDay()
        guard nutritionDay.isLateNight == false else {
            return nil
        }

        return (syntheticNutritionRecord(for: nutritionDay.today), MacrosData(
            protein: 0,
            proteinTarget: 180,
            carbs: 0,
            carbsTarget: 386,
            fat: 0,
            fatTarget: 110,
            date: nutritionDay.today
        ))
    }

    private func syntheticNutritionRecord(for date: String) -> Record {
        Record(
            id: syntheticNutritionRecordID,
            agentId: "theperch-ui",
            userId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            type: .measurement,
            category: .health,
            title: "Daily Nutrition",
            data: .object(["date": .string(date)]),
            displayHint: .singleValue,
            annotations: nil,
            pinned: false,
            createdAt: now(),
            updatedAt: now(),
            expiresAt: nil
        )
    }

    private func currentNutritionDay() -> (today: String, yesterday: String, isLateNight: Bool) {
        let currentDate = now()
        let today = PerchFormatters.isoDate.string(from: currentDate)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
        let yesterday = PerchFormatters.isoDate.string(from: yesterdayDate)
        let isLateNight = calendar.component(.hour, from: currentDate) < 2
        return (today, yesterday, isLateNight)
    }

    /// Ordered list of chart metrics to display (body comp → sleep → nutrition).
    static let chartMetricOrder: [(key: String, title: String, unit: String, emoji: String, higherIsBetter: Bool)] = [
        ("weight", "Weight", "kg", "⚖️", false),
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
        return PerchFormatters.relativeDateTime.localizedString(for: lastSyncDate, relativeTo: Date())
    }
}
