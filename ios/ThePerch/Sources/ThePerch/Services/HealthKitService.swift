import Foundation
import HealthKit

// MARK: - Error Types

/// Errors that can occur during HealthKit operations.
enum HealthKitServiceError: LocalizedError {
    case notAvailable
    case permissionDenied(String)
    case queryError(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .permissionDenied(let message):
            return "Health permission denied: \(message)"
        case .queryError(let message):
            return "HealthKit query error: \(message)"
        }
    }
}

// MARK: - HealthKit Sample Wrapper

/// A lightweight wrapper around a HealthKit sample for use in the app.
struct HealthKitSample: Identifiable {
    let id: UUID
    let metric: String
    let value: Double
    let unit: String
    let timestamp: Date
    let source: String

    /// Secondary value for composite metrics like blood pressure (diastolic).
    let secondaryValue: Double?

    init(
        metric: String,
        value: Double,
        unit: String,
        timestamp: Date,
        source: String = "Apple Health (iPhone)",
        secondaryValue: Double? = nil
    ) {
        self.id = UUID()
        self.metric = metric
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.source = source
        self.secondaryValue = secondaryValue
    }
}

// MARK: - HealthKitService

/// Service for reading health data from Apple Health.
/// Follows the same singleton pattern as EventKitService.
@MainActor
final class HealthKitService: NSObject, HealthKitServiceProtocol {
    static let shared = HealthKitService()

    private let healthStore: HKHealthStore?

    /// Whether HealthKit is available on this device.
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Initialization

    private override init() {
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
        } else {
            self.healthStore = nil
        }
        super.init()
    }

    // MARK: - Authorization

    /// The set of HealthKit types we want to read.
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(weight)
        }
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let systolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic) {
            types.insert(systolic)
        }
        if let diastolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            types.insert(diastolic)
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }

        return types
    }

    /// Requests read-only authorization for all health metrics.
    /// - Returns: True if authorization was granted (or already available).
    func requestAuthorization() async -> Bool {
        guard let healthStore else {
            print("[HealthKitService] HealthKit not available on this device")
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            print("[HealthKitService] Authorization granted")
            return true
        } catch {
            print("[HealthKitService] Authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Fetching Weight

    /// Fetches weight samples from the last N days.
    func fetchWeight(days: Int = 30) async throws -> [HealthKitSample] {
        guard let healthStore else { throw HealthKitServiceError.notAvailable }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return []
        }

        let samples = try await querySamples(
            healthStore: healthStore,
            quantityType: quantityType,
            days: days
        )

        return samples.compactMap { sample in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            let kg = quantitySample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            return HealthKitSample(
                metric: "weight",
                value: round(kg * 10) / 10,
                unit: "kg",
                timestamp: quantitySample.startDate,
                source: sourceDescription(quantitySample)
            )
        }
    }

    // MARK: - Fetching Heart Rate

    /// Fetches heart rate samples from the last N days.
    func fetchHeartRate(days: Int = 7) async throws -> [HealthKitSample] {
        guard let healthStore else { throw HealthKitServiceError.notAvailable }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }

        let samples = try await querySamples(
            healthStore: healthStore,
            quantityType: quantityType,
            days: days
        )

        return samples.compactMap { sample in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            let bpm = quantitySample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            return HealthKitSample(
                metric: "heart_rate",
                value: round(bpm),
                unit: "bpm",
                timestamp: quantitySample.startDate,
                source: sourceDescription(quantitySample)
            )
        }
    }

    // MARK: - Fetching Blood Pressure

    /// Fetches blood pressure correlation samples from the last N days.
    func fetchBloodPressure(days: Int = 30) async throws -> [HealthKitSample] {
        guard let healthStore else { throw HealthKitServiceError.notAvailable }
        guard let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return []
        }

        // Fetch systolic samples
        let systolicSamples = try await querySamples(
            healthStore: healthStore,
            quantityType: systolicType,
            days: days
        )

        // Fetch diastolic samples
        let diastolicSamples = try await querySamples(
            healthStore: healthStore,
            quantityType: diastolicType,
            days: days
        )

        // Match systolic and diastolic by timestamp proximity
        let mmHg = HKUnit.millimeterOfMercury()

        return systolicSamples.compactMap { sysSample in
            guard let sysQuantity = sysSample as? HKQuantitySample else { return nil }
            let systolicValue = sysQuantity.quantity.doubleValue(for: mmHg)

            // Find the closest diastolic sample within 60 seconds
            let diastolicValue = diastolicSamples
                .compactMap { $0 as? HKQuantitySample }
                .first { abs($0.startDate.timeIntervalSince(sysQuantity.startDate)) < 60 }
                .map { $0.quantity.doubleValue(for: mmHg) }

            return HealthKitSample(
                metric: "blood_pressure",
                value: round(systolicValue),
                unit: "mmHg",
                timestamp: sysQuantity.startDate,
                source: sourceDescription(sysQuantity),
                secondaryValue: diastolicValue.map { round($0) }
            )
        }
    }

    // MARK: - Fetching Steps

    /// Fetches step count for the last N days, aggregated by day.
    func fetchSteps(days: Int = 1) async throws -> [HealthKitSample] {
        guard let healthStore else { throw HealthKitServiceError.notAvailable }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return []
        }

        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -days, to: now) ?? now)

        // Use a statistics collection query to aggregate steps by day
        let interval = DateComponents(day: 1)
        let anchorDate = calendar.startOfDay(for: now)

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)

        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchorDate,
            intervalComponents: interval
        )

        return try await withCheckedThrowingContinuation { continuation in
            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: HealthKitServiceError.queryError(error.localizedDescription))
                    return
                }

                var samples: [HealthKitSample] = []
                results?.enumerateStatistics(from: startDate, to: now) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        let steps = sum.doubleValue(for: .count())
                        samples.append(HealthKitSample(
                            metric: "steps",
                            value: round(steps),
                            unit: "steps",
                            timestamp: statistics.startDate
                        ))
                    }
                }
                continuation.resume(returning: samples)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Fetching Sleep

    /// Fetches sleep analysis from the last N days, returning total hours per night.
    func fetchSleep(days: Int = 7) async throws -> [HealthKitSample] {
        guard let healthStore else { throw HealthKitServiceError.notAvailable }
        guard let categoryType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: now) ?? now

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: HealthKitServiceError.queryError(error.localizedDescription))
                } else {
                    continuation.resume(returning: results ?? [])
                }
            }
            healthStore.execute(query)
        }

        // Group by night and sum duration for asleep stages
        var nightlyHours: [String: Double] = [:]
        let dateFormatter = PerchFormatters.isoDate

        for sample in samples {
            guard let categorySample = sample as? HKCategorySample else { continue }

            // Only count "asleep" stages (not inBed or awake)
            let value = categorySample.value
            let isAsleep = value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue

            guard isAsleep else { continue }

            let nightKey = dateFormatter.string(from: categorySample.startDate)
            let hours = categorySample.endDate.timeIntervalSince(categorySample.startDate) / 3600.0
            nightlyHours[nightKey, default: 0] += hours
        }

        return nightlyHours.map { nightKey, hours in
            let date = dateFormatter.date(from: nightKey) ?? now
            return HealthKitSample(
                metric: "sleep",
                value: round(hours * 10) / 10,
                unit: "hours",
                timestamp: date
            )
        }.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Private Helpers

    /// Generic query for quantity type samples.
    private func querySamples(
        healthStore: HKHealthStore,
        quantityType: HKQuantityType,
        days: Int
    ) async throws -> [HKSample] {
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: now) ?? now

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: HealthKitServiceError.queryError(error.localizedDescription))
                } else {
                    continuation.resume(returning: results ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    /// Extracts a human-readable source description from a sample.
    private func sourceDescription(_ sample: HKSample) -> String {
        let sourceName = sample.sourceRevision.source.name
        return "Apple Health (\(sourceName))"
    }
}
