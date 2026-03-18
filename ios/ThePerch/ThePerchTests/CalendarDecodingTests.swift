import Foundation
import Testing
@testable import ThePerch

// MARK: - Calendar & Event Decoding Tests
// These tests prevent regressions on the issues that caused Builds 36-42 to fail:
// 1. Wrong Supabase field names (start_time vs start)
// 2. Wrong record type ("calendario" vs "event")
// 3. Unknown enum values crashing instead of falling back

@Suite("RecordType Enum Completeness")
struct RecordTypeTests {

    @Test("All known raw values decode to their correct case")
    func decodesKnownTypes() {
        let knownTypes: [(String, RecordType)] = [
            ("measurement", .measurement),
            ("delivery", .delivery),
            ("event", .event),
            ("status", .status),
            ("reminder", .reminder),
            ("text_note", .textNote),
            ("checklist", .checklist),
            ("cost_summary", .costSummary),
            ("bookmark", .bookmark),
            ("command", .command),
            ("trip", .trip),
            ("itinerary", .itinerary),
            ("travel_alert", .travelAlert),
            ("weather_forecast", .weatherForecast),
            ("travel_task", .travelTask),
            ("workout_session", .workoutSession),
            ("calendar_event", .calendarEvent),
        ]

        for (rawValue, expected) in knownTypes {
            let type = RecordType(rawValue: rawValue)
            #expect(type != nil, "RecordType should decode '\(rawValue)'")
            #expect(type != .unknown, "RecordType '\(rawValue)' decoded as .unknown")
            #expect(type == expected, "RecordType '\(rawValue)' should be .\(expected) but got \(String(describing: type))")
        }
    }

    @Test("Unknown raw values fall back to .unknown (not crash)")
    func unknownFallsBack() {
        // "calendario" was the old wrong value that caused the calendar bug
        let type = RecordType(rawValue: "calendario")
        #expect(type == .unknown, "Unknown raw value should decode as .unknown")
    }
}

@Suite("RecordCategory Enum Completeness")
struct RecordCategoryTests {

    @Test("All known categories decode correctly")
    func decodesKnownCategories() {
        let known: [(String, RecordCategory)] = [
            ("health", .health),
            ("workouts", .workouts),
            ("deliveries", .deliveries),
            ("calendar", .calendar),
            ("admin", .admin),
            ("legal", .legal),
            ("bookmarks", .bookmarks),
            ("travel", .travel),
        ]

        for (rawValue, expected) in known {
            let cat = RecordCategory(rawValue: rawValue)
            #expect(cat != nil, "RecordCategory should decode '\(rawValue)'")
            #expect(cat == expected)
        }
    }
}

@Suite("DisplayHint Enum Completeness")
struct DisplayHintTests {

    @Test("All known display hints decode correctly")
    func decodesKnownHints() {
        let known: [(String, DisplayHint)] = [
            ("chart", .chart),
            ("single_value", .singleValue),
            ("status_list", .statusList),
            ("timeline", .timeline),
            ("checklist", .checklist),
            ("cost_breakdown", .costBreakdown),
            ("bookmark_card", .bookmarkCard),
            ("bookmark_grid", .bookmarkGrid),
            ("progress_gauge", .progressGauge),
            ("macros_bar", .macrosBar),
            ("calendar_event", .calendarEvent),
        ]

        for (rawValue, expected) in known {
            let hint = DisplayHint(rawValue: rawValue)
            #expect(hint != nil, "DisplayHint should decode '\(rawValue)'")
            #expect(hint == expected)
        }
    }
}

@Suite("EventData Decoding")
struct EventDataDecodingTests {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test("Decodes with correct field names (start/end)")
    func decodesCorrectFields() throws {
        let json = """
        {
            "title": "Gym",
            "start": "2026-03-18T08:15:00Z",
            "end": "2026-03-18T09:15:00Z",
            "location": "Holmes Place Amoreiras"
        }
        """.data(using: .utf8)!

        let event = try decoder.decode(EventData.self, from: json)
        #expect(event.title == "Gym")
        #expect(event.location == "Holmes Place Amoreiras")
    }

    @Test("Rejects wrong field names (start_time/end_time)")
    func rejectsWrongFields() {
        let json = """
        {
            "title": "Gym",
            "start_time": "2026-03-18T08:15:00Z",
            "end_time": "2026-03-18T09:15:00Z"
        }
        """.data(using: .utf8)!

        let event = try? decoder.decode(EventData.self, from: json)
        #expect(event == nil, "EventData should NOT decode with start_time/end_time")
    }

    @Test("Handles optional location gracefully")
    func optionalLocation() throws {
        let json = """
        {
            "title": "Break",
            "start": "2026-03-18T12:00:00Z",
            "end": "2026-03-18T13:00:00Z"
        }
        """.data(using: .utf8)!

        let event = try decoder.decode(EventData.self, from: json)
        #expect(event.title == "Break")
        #expect(event.location == nil)
    }
}
