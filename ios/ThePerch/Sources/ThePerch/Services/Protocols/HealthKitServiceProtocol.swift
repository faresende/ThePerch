import Foundation

/// Protocol defining the interface for HealthKit data operations.
/// Enables dependency injection and mock implementations for testing/previews.
@MainActor
protocol HealthKitServiceProtocol: AnyObject {
    var isAvailable: Bool { get }
    func requestAuthorization() async -> Bool
    func fetchWeight(days: Int) async throws -> [HealthKitSample]
    func fetchHeartRate(days: Int) async throws -> [HealthKitSample]
    func fetchBloodPressure(days: Int) async throws -> [HealthKitSample]
    func fetchSteps(days: Int) async throws -> [HealthKitSample]
    func fetchSleep(days: Int) async throws -> [HealthKitSample]
}
