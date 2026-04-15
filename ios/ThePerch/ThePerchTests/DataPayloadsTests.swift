import Foundation
import Testing
@testable import ThePerch

// MARK: - MeasurementData Decoding Tests

@Suite("MeasurementData JSON Decoding")
struct MeasurementDataTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test("Decodes full measurement payload")
    func decodesFullPayload() throws {
        let json = """
        {
            "metric": "weight",
            "value": 185.5,
            "unit": "lbs",
            "context": "morning weigh-in",
            "target": 180.0,
            "display_value": "185.5"
        }
        """.data(using: .utf8)!

        let m = try decoder.decode(MeasurementData.self, from: json)
        #expect(m.metric == "weight")
        #expect(m.value == 185.5)
        #expect(m.unit == "lbs")
        #expect(m.context == "morning weigh-in")
        #expect(m.target == 180.0)
        #expect(m.displayValue == "185.5")
    }

    @Test("Decodes measurement with only required fields")
    func decodesMinimalPayload() throws {
        let json = """
        {"metric": "steps", "value": 8500, "unit": "steps"}
        """.data(using: .utf8)!

        let m = try decoder.decode(MeasurementData.self, from: json)
        #expect(m.metric == "steps")
        #expect(m.value == 8500)
        #expect(m.unit == "steps")
        #expect(m.context == nil)
        #expect(m.target == nil)
        #expect(m.displayValue == nil)
        #expect(m.timestamp == nil)
    }
}

// MARK: - DeliveryData Decoding Tests

@Suite("DeliveryData JSON Decoding")
struct DeliveryDataTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test("Decodes delivery with items")
    func decodesDeliveryPayload() throws {
        let json = """
        {
            "order_id": "ORD-123",
            "carrier": "UPS",
            "tracking_number": "1Z999AA10123456784",
            "status": "in_transit",
            "items": [
                {"name": "Wireless Mouse", "quantity": 1, "description": "Ergonomic mouse"},
                {"name": "USB-C Cable", "quantity": 2, "description": null}
            ],
            "tracking_url": "https://example.com/track"
        }
        """.data(using: .utf8)!

        let d = try decoder.decode(DeliveryData.self, from: json)
        #expect(d.orderId == "ORD-123")
        #expect(d.carrier == "UPS")
        #expect(d.trackingNumber == "1Z999AA10123456784")
        #expect(d.status == "in_transit")
        #expect(d.items.count == 2)
        #expect(d.items[0].name == "Wireless Mouse")
        #expect(d.items[1].quantity == 2)
        #expect(d.trackingUrl == "https://example.com/track")
        #expect(d.eta == nil)
    }
}

// MARK: - BookmarkData Decoding Tests

@Suite("BookmarkData JSON Decoding")
struct BookmarkDataTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test("Decodes processed bookmark")
    func decodesProcessedBookmark() throws {
        let json = """
        {
            "url": "https://example.com/article",
            "original_title": "Original Title",
            "enriched_title": "Better Title",
            "summary": "A short summary",
            "tags": ["swift", "ios"],
            "status": "processed",
            "domain": "example.com",
            "reading_time_minutes": 5,
            "submitted_from": "ios_share"
        }
        """.data(using: .utf8)!

        let b = try decoder.decode(BookmarkData.self, from: json)
        #expect(b.url == "https://example.com/article")
        #expect(b.enrichedTitle == "Better Title")
        #expect(b.status == .processed)
        #expect(b.tags == ["swift", "ios"])
        #expect(b.readingTimeMinutes == 5)
        #expect(b.submittedFrom == "ios_share")
    }

    @Test("displayTitle prefers enrichedTitle")
    func displayTitlePrefersEnriched() throws {
        let json = """
        {
            "url": "https://example.com",
            "original_title": "Original",
            "enriched_title": "Enriched",
            "tags": [],
            "status": "processed"
        }
        """.data(using: .utf8)!

        let b = try decoder.decode(BookmarkData.self, from: json)
        #expect(b.displayTitle == "Enriched")
    }

    @Test("displayTitle falls back to originalTitle then domain then url")
    func displayTitleFallback() throws {
        // No enrichedTitle → originalTitle
        let json1 = """
        {"url": "https://example.com", "original_title": "Original", "tags": [], "status": "pending", "domain": "example.com"}
        """.data(using: .utf8)!
        let b1 = try decoder.decode(BookmarkData.self, from: json1)
        #expect(b1.displayTitle == "Original")

        // No enrichedTitle, no originalTitle → domain
        let json2 = """
        {"url": "https://example.com", "tags": [], "status": "pending", "domain": "example.com"}
        """.data(using: .utf8)!
        let b2 = try decoder.decode(BookmarkData.self, from: json2)
        #expect(b2.displayTitle == "example.com")

        // Nothing → url
        let json3 = """
        {"url": "https://example.com/path", "tags": [], "status": "pending"}
        """.data(using: .utf8)!
        let b3 = try decoder.decode(BookmarkData.self, from: json3)
        #expect(b3.displayTitle == "https://example.com/path")
    }
}

// MARK: - Capture Launcher Helpers

@Suite("Capture launcher helpers")
struct CaptureLauncherHelperTests {
    @Test("primary actions keep meal first and quick note second")
    func primaryActionsOrder() {
        #expect(CaptureActionOption.primaryActions == [.logMeal, .quickNote])
    }

    @Test("quick note title uses first non-empty line")
    func quickNoteTitleUsesFirstLine() {
        let draft = QuickNoteDraft(body: "\n  Pick up blazer from tailor\nAnd confirm Friday dinner")
        #expect(draft.trimmedBody == "Pick up blazer from tailor\nAnd confirm Friday dinner")
        #expect(draft.derivedTitle == "Pick up blazer from tailor")
    }

    @Test("quick note falls back to generic title when blank")
    func quickNoteFallsBackWhenBlank() {
        let draft = QuickNoteDraft(body: "   \n   ")
        #expect(draft.trimmedBody == nil)
        #expect(draft.derivedTitle == "Quick Note")
    }
}
