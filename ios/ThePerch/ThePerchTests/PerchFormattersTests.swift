import Foundation
import Testing
@testable import ThePerch

@Suite("PerchFormatters")
struct PerchFormattersTests {
    @Test("isoDate formats and parses yyyy-MM-dd")
    func isoDateRoundTrip() throws {
        let dateString = "2026-03-08"
        let date = try #require(PerchFormatters.isoDate.date(from: dateString))
        let formatted = PerchFormatters.isoDate.string(from: date)
        #expect(formatted == dateString)
    }

    @Test("shortDate produces MMM d format")
    func shortDateFormat() throws {
        let date = try #require(PerchFormatters.isoDate.date(from: "2026-03-08"))
        let result = PerchFormatters.shortDate.string(from: date)
        #expect(result == "Mar 8")
    }

    @Test("decimal formatter limits to 2 fraction digits")
    func decimalFormatter() {
        let result = PerchFormatters.decimal.string(from: NSNumber(value: 1234.567))
        // Locale-independent check: should have at most 2 decimal digits
        #expect(result != nil)
        // Verify the formatter's configuration directly
        #expect(PerchFormatters.decimal.maximumFractionDigits == 2)
        #expect(PerchFormatters.decimal.numberStyle == .decimal)
    }

    @Test("percent formatter uses 0 fraction digits")
    func percentFormatter() {
        #expect(PerchFormatters.percent.maximumFractionDigits == 0)
        #expect(PerchFormatters.percent.numberStyle == .percent)
        // Verify it produces a non-nil result
        let result = PerchFormatters.percent.string(from: NSNumber(value: 0.856))
        #expect(result != nil)
    }
}
