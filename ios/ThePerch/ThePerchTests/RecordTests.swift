import Foundation
import Testing
@testable import ThePerch

@Suite("Record")
struct RecordTests {
    /// Helper to create a Record with given data.
    private func makeRecord(
        type: RecordType = .measurement,
        category: RecordCategory = .health,
        title: String = "Test",
        data: JSONValue = .object([:]),
        displayHint: DisplayHint = .singleValue,
        createdAt: Date = .now,
        expiresAt: Date? = nil
    ) -> Record {
        Record(
            id: UUID(),
            agentId: "test-agent",
            userId: UUID(),
            type: type,
            category: category,
            title: title,
            data: data,
            displayHint: displayHint,
            annotations: nil,
            pinned: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            expiresAt: expiresAt
        )
    }

    @Test("isExpired returns false when no expiresAt")
    func notExpiredWhenNil() {
        let record = makeRecord()
        #expect(!record.isExpired)
    }

    @Test("isExpired returns true for past date")
    func expiredForPastDate() {
        let record = makeRecord(expiresAt: Date.distantPast)
        #expect(record.isExpired)
    }

    @Test("isExpired returns false for future date")
    func notExpiredForFutureDate() {
        let record = makeRecord(expiresAt: Date.distantFuture)
        #expect(!record.isExpired)
    }

    @Test("decodeData successfully decodes MeasurementData from JSONValue")
    func decodeDataMeasurement() {
        let data: JSONValue = .object([
            "metric": .string("weight"),
            "value": .double(185.0),
            "unit": .string("lbs"),
        ])
        let record = makeRecord(data: data)
        let measurement = record.asMeasurement()
        #expect(measurement != nil)
        #expect(measurement?.metric == "weight")
        #expect(measurement?.value == 185.0)
    }

    @Test("decodeData returns nil for incompatible data")
    func decodeDataReturnsNilForBadData() {
        let data: JSONValue = .object(["foo": .string("bar")])
        let record = makeRecord(type: .delivery, data: data)
        let delivery = record.asDelivery()
        #expect(delivery == nil)
    }

    @Test("RecordType displayName returns human-readable strings")
    func recordTypeDisplayNames() {
        #expect(RecordType.measurement.displayName == "Measurement")
        #expect(RecordType.textNote.displayName == "Text Note")
        #expect(RecordType.costSummary.displayName == "Cost Summary")
    }

    @Test("RecordCategory displayName returns human-readable strings")
    func categoryDisplayNames() {
        #expect(RecordCategory.health.displayName == "Health")
        #expect(RecordCategory.deliveries.displayName == "Deliveries")
        #expect(RecordCategory.bookmarks.displayName == "Bookmarks")
    }
}

@Suite("HealthViewModel nutrition day selection")
struct HealthViewModelNutritionSelectionTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeMacrosRecord(date: String, updatedAt: Date) -> Record {
        Record(
            id: UUID(),
            agentId: "test-agent",
            userId: UUID(),
            type: .measurement,
            category: .health,
            title: "Daily Macros",
            data: .object([
                "protein": .double(180),
                "protein_target": .double(180),
                "carbs": .double(300),
                "carbs_target": .double(350),
                "fat": .double(90),
                "fat_target": .double(100),
                "date": .string(date),
            ]),
            displayHint: .macrosBar,
            annotations: nil,
            pinned: false,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            expiresAt: nil
        )
    }

    private func makeCaloriesRecord(context: String, value: Double, updatedAt: Date) -> Record {
        Record(
            id: UUID(),
            agentId: "test-agent",
            userId: UUID(),
            type: .measurement,
            category: .health,
            title: "Daily Calories",
            data: .object([
                "metric": .string("daily_calories"),
                "value": .double(value),
                "unit": .string("kcal"),
                "target": .double(3400),
                "context": .string(context),
            ]),
            displayHint: .progressGauge,
            annotations: nil,
            pinned: false,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            expiresAt: nil
        )
    }

    @MainActor
    @Test("After 2am, Health macros only shows today's record")
    func latestMacrosAfter2amRequiresTodayData() {
        let now = ISO8601DateFormatter().date(from: "2026-03-20T07:11:00Z")!
        let yesterdayUpdate = ISO8601DateFormatter().date(from: "2026-03-19T21:24:00Z")!
        let viewModel = HealthViewModel(
            syncService: .shared,
            calendar: calendar,
            now: { now }
        )
        viewModel.records = [makeMacrosRecord(date: "2026-03-19", updatedAt: yesterdayUpdate)]

        #expect(viewModel.latestMacros == nil)
    }

    @MainActor
    @Test("Before 2am, Health macros falls back to yesterday's final tally")
    func latestMacrosBefore2amFallsBackToYesterday() {
        let now = ISO8601DateFormatter().date(from: "2026-03-20T01:30:00Z")!
        let yesterdayUpdate = ISO8601DateFormatter().date(from: "2026-03-19T21:24:00Z")!
        let viewModel = HealthViewModel(
            syncService: .shared,
            calendar: calendar,
            now: { now }
        )
        viewModel.records = [makeMacrosRecord(date: "2026-03-19", updatedAt: yesterdayUpdate)]

        #expect(viewModel.latestMacros?.1.date == "2026-03-19")
    }

    @MainActor
    @Test("After 2am, Health calories only shows today's record")
    func latestDailyCaloriesAfter2amRequiresTodayData() {
        let now = ISO8601DateFormatter().date(from: "2026-03-20T07:11:00Z")!
        let yesterdayUpdate = ISO8601DateFormatter().date(from: "2026-03-19T21:24:00Z")!
        let viewModel = HealthViewModel(
            syncService: .shared,
            calendar: calendar,
            now: { now }
        )
        viewModel.records = [makeCaloriesRecord(context: "2026-03-19", value: 3299, updatedAt: yesterdayUpdate)]

        #expect(viewModel.latestDailyCalories == nil)
    }

    @MainActor
    @Test("After 2am, Health exposes a zero calories state when nothing is logged today")
    func displayedCaloriesAfter2amFallsBackToZeroState() {
        let now = ISO8601DateFormatter().date(from: "2026-03-20T07:11:00Z")!
        let yesterdayUpdate = ISO8601DateFormatter().date(from: "2026-03-19T21:24:00Z")!
        let viewModel = HealthViewModel(
            syncService: .shared,
            calendar: calendar,
            now: { now }
        )
        viewModel.records = [makeCaloriesRecord(context: "2026-03-19", value: 3299, updatedAt: yesterdayUpdate)]

        let displayed = viewModel.displayedDailyCalories
        #expect(displayed?.1.value == 0)
        #expect(displayed?.1.target == 3400)
        #expect(displayed?.1.context == "2026-03-20")
        #expect(displayed?.0.id == viewModel.syntheticNutritionRecordID)
    }

    @MainActor
    @Test("After 2am, Health exposes zero macros when nothing is logged today")
    func displayedMacrosAfter2amFallsBackToZeroState() {
        let now = ISO8601DateFormatter().date(from: "2026-03-20T07:11:00Z")!
        let yesterdayUpdate = ISO8601DateFormatter().date(from: "2026-03-19T21:24:00Z")!
        let viewModel = HealthViewModel(
            syncService: .shared,
            calendar: calendar,
            now: { now }
        )
        viewModel.records = [makeMacrosRecord(date: "2026-03-19", updatedAt: yesterdayUpdate)]

        let displayed = viewModel.displayedMacros
        #expect(displayed?.1.protein == 0)
        #expect(displayed?.1.carbs == 0)
        #expect(displayed?.1.fat == 0)
        #expect(displayed?.1.date == "2026-03-20")
        #expect(displayed?.0.id == viewModel.syntheticNutritionRecordID)
    }
}

@Suite("WorkoutSessionFeedCard stat ordering")
struct WorkoutSessionFeedCardTests {
    private func makeSession(avgHr: Int? = 145, calories: Int? = 612) -> WorkoutSessionData {
        WorkoutSessionData(
            sessionNumber: 3,
            date: "2026-03-20",
            muscleGroups: ["push"],
            durationMin: 68,
            activeCalories: calories,
            avgHr: avgHr,
            maxHr: 171,
            exercises: [
                WorkoutExercise(
                    name: "Bench Press",
                    sets: [
                        WorkoutSet(weightKg: 90, reps: 5, durationSec: nil, notes: nil),
                        WorkoutSet(weightKg: 95, reps: 3, durationSec: nil, notes: nil)
                    ],
                    notes: nil
                )
            ],
            progressiveOverload: nil
        )
    }

    @Test("Expanded and collapsed workout summary stats use the same leading order")
    func workoutSummaryStatsUseSameLeadingOrder() {
        let session = makeSession()
        let expanded = WorkoutSessionFeedCard.summaryStats(for: session, isExpanded: true).map(\.value)
        let collapsed = WorkoutSessionFeedCard.summaryStats(for: session, isExpanded: false).map(\.value)

        #expect(expanded.prefix(2).elementsEqual(["2 sets", "612 cal"]))
        #expect(collapsed.prefix(2).elementsEqual(["2 sets", "612 cal"]))
    }

    @Test("Workout collapsed state still includes top lift after primary stats")
    func workoutCollapsedStateKeepsTopLiftAsTertiaryStat() {
        let session = makeSession()
        let collapsed = WorkoutSessionFeedCard.summaryStats(for: session, isExpanded: false).map(\.value)

        #expect(collapsed.count == 3)
        #expect(collapsed[2] == "Bench Press 95kg")
    }
}
