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
