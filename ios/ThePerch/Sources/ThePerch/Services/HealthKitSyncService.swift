import Foundation

// MARK: - Sync State

/// Tracks the last sync date per metric type in UserDefaults.
private enum SyncStateKey {
    static let prefix = "healthkit_last_sync_"

    static func key(for metric: String) -> String {
        "\(prefix)\(metric)"
    }

    static func lastSync(for metric: String) -> Date? {
        UserDefaults.standard.object(forKey: key(for: metric)) as? Date
    }

    static func setLastSync(for metric: String, date: Date) {
        UserDefaults.standard.set(date, forKey: key(for: metric))
    }

    static var lastSyncAny: Date? {
        let metrics = ["weight", "heart_rate", "blood_pressure", "steps", "sleep"]
        return metrics.compactMap { lastSync(for: $0) }.max()
    }
}

// MARK: - HealthKitSyncService

/// Orchestrates syncing health data from HealthKit to Supabase.
/// Reads from HealthKitService, deduplicates via UserDefaults timestamps,
/// and writes new records to Supabase via SupabaseService.insertRecord().
@MainActor
final class HealthKitSyncService {
    static let shared = HealthKitSyncService()

    private let healthKitService: HealthKitService
    private let supabaseService: SupabaseService

    /// Fabio's user ID in Supabase.
    private let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// The agent_id used for HealthKit-sourced records.
    private let agentId = "healthkit"

    // MARK: - State

    var isSyncing: Bool = false
    var lastSyncDate: Date? { SyncStateKey.lastSyncAny }
    var syncError: String?
    var syncedCount: Int = 0

    // MARK: - Initialization

    private init(
        healthKitService: HealthKitService = .shared,
        supabaseService: SupabaseService = .shared
    ) {
        self.healthKitService = healthKitService
        self.supabaseService = supabaseService
    }

    // MARK: - Sync All Metrics

    /// Syncs all supported health metrics from HealthKit to Supabase.
    /// Only syncs samples newer than the last sync date for each metric.
    func syncAll() async {
        guard !isSyncing else {
            print("[HealthKitSync] Already syncing, skipping")
            return
        }

        isSyncing = true
        syncError = nil
        syncedCount = 0

        defer { isSyncing = false }

        // Request authorization first
        let authorized = await healthKitService.requestAuthorization()
        guard authorized else {
            syncError = "Health data access not granted. Please enable in Settings > Privacy > Health."
            print("[HealthKitSync] Authorization denied")
            return
        }

        // Sync each metric type independently so one failure doesn't block others
        await syncWeight()
        await syncHeartRate()
        await syncBloodPressure()
        await syncSteps()
        await syncSleep()

        print("[HealthKitSync] Sync complete. \(syncedCount) new records written.")
    }

    // MARK: - Individual Metric Syncs

    private func syncWeight() async {
        do {
            let samples = try await healthKitService.fetchWeight(days: 30)
            let newSamples = filterNew(samples, metric: "weight")
            for sample in newSamples {
                try await writeSample(sample, title: "Weight")
            }
            if !newSamples.isEmpty {
                SyncStateKey.setLastSync(for: "weight", date: Date())
            }
            print("[HealthKitSync] Weight: \(newSamples.count) new samples")
        } catch {
            print("[HealthKitSync] Weight sync error: \(error.localizedDescription)")
        }
    }

    private func syncHeartRate() async {
        do {
            let samples = try await healthKitService.fetchHeartRate(days: 7)
            let newSamples = filterNew(samples, metric: "heart_rate")

            // For heart rate, only sync the most recent reading per day to avoid flooding
            let dailySamples = mostRecentPerDay(newSamples)
            for sample in dailySamples {
                try await writeSample(sample, title: "Heart Rate")
            }
            if !dailySamples.isEmpty {
                SyncStateKey.setLastSync(for: "heart_rate", date: Date())
            }
            print("[HealthKitSync] Heart Rate: \(dailySamples.count) new samples")
        } catch {
            print("[HealthKitSync] Heart Rate sync error: \(error.localizedDescription)")
        }
    }

    private func syncBloodPressure() async {
        do {
            let samples = try await healthKitService.fetchBloodPressure(days: 30)
            let newSamples = filterNew(samples, metric: "blood_pressure")
            for sample in newSamples {
                try await writeBloodPressureSample(sample, title: "Blood Pressure")
            }
            if !newSamples.isEmpty {
                SyncStateKey.setLastSync(for: "blood_pressure", date: Date())
            }
            print("[HealthKitSync] Blood Pressure: \(newSamples.count) new samples")
        } catch {
            print("[HealthKitSync] Blood Pressure sync error: \(error.localizedDescription)")
        }
    }

    private func syncSteps() async {
        do {
            let samples = try await healthKitService.fetchSteps(days: 1)
            let newSamples = filterNew(samples, metric: "steps")
            for sample in newSamples {
                try await writeSample(sample, title: "Steps")
            }
            if !newSamples.isEmpty {
                SyncStateKey.setLastSync(for: "steps", date: Date())
            }
            print("[HealthKitSync] Steps: \(newSamples.count) new samples")
        } catch {
            print("[HealthKitSync] Steps sync error: \(error.localizedDescription)")
        }
    }

    private func syncSleep() async {
        do {
            let samples = try await healthKitService.fetchSleep(days: 7)
            let newSamples = filterNew(samples, metric: "sleep")
            for sample in newSamples {
                try await writeSample(sample, title: "Sleep")
            }
            if !newSamples.isEmpty {
                SyncStateKey.setLastSync(for: "sleep", date: Date())
            }
            print("[HealthKitSync] Sleep: \(newSamples.count) new samples")
        } catch {
            print("[HealthKitSync] Sleep sync error: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Filters samples to only include those newer than the last sync date.
    private func filterNew(_ samples: [HealthKitSample], metric: String) -> [HealthKitSample] {
        guard let lastSync = SyncStateKey.lastSync(for: metric) else {
            return samples // First sync: include all
        }
        return samples.filter { $0.timestamp > lastSync }
    }

    /// Returns only the most recent sample per calendar day (to avoid flooding).
    private func mostRecentPerDay(_ samples: [HealthKitSample]) -> [HealthKitSample] {
        let calendar = Calendar.current
        var byDay: [String: HealthKitSample] = [:]
        for sample in samples {
            let dayKey = PerchFormatters.isoDate.string(from: sample.timestamp)
            if let existing = byDay[dayKey] {
                if sample.timestamp > existing.timestamp {
                    byDay[dayKey] = sample
                }
            } else {
                byDay[dayKey] = sample
            }
        }
        return Array(byDay.values).sorted { $0.timestamp > $1.timestamp }
    }

    /// Writes a standard health sample to Supabase as a dashboard_record.
    private func writeSample(_ sample: HealthKitSample, title: String) async throws {
        let data: [String: JSONValue] = [
            "metric": .string(sample.metric),
            "value": .double(sample.value),
            "unit": .string(sample.unit),
            "context": .string(sample.source),
            "timestamp": .string(PerchFormatters.iso8601.string(from: sample.timestamp))
        ]

        try await supabaseService.insertRecord(
            agentId: agentId,
            userId: userId,
            type: .measurement,
            category: .health,
            title: title,
            data: data,
            displayHint: .singleValue
        )
        syncedCount += 1
    }

    /// Writes a blood pressure sample with systolic/diastolic as a formatted value.
    private func writeBloodPressureSample(_ sample: HealthKitSample, title: String) async throws {
        let displayValue: String
        if let diastolic = sample.secondaryValue {
            displayValue = "\(Int(sample.value))/\(Int(diastolic))"
        } else {
            displayValue = "\(Int(sample.value))"
        }

        let data: [String: JSONValue] = [
            "metric": .string(sample.metric),
            "value": .double(sample.value),
            "unit": .string(sample.unit),
            "context": .string(sample.source),
            "timestamp": .string(PerchFormatters.iso8601.string(from: sample.timestamp)),
            "display_value": .string(displayValue),
            "diastolic": sample.secondaryValue.map { .double($0) } ?? .null
        ]

        try await supabaseService.insertRecord(
            agentId: agentId,
            userId: userId,
            type: .measurement,
            category: .health,
            title: title,
            data: data,
            displayHint: .singleValue
        )
        syncedCount += 1
    }
}
