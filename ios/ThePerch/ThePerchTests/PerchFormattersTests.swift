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

    @Test("ChartCard trend badge uses absolute kilograms for weight")
    func chartCardTrendBadgeUsesAbsoluteKilograms() {
        let result = ChartCard.trendBadgeText(current: 95.1, baseline: 92.6, unit: "kg", formatAsTime: false)
        #expect(result.contains("kg"))
        #expect(result.contains("2.5") || result.contains("2,5"))
    }

    @Test("ChartCard trend badge uses percentage points for body fat")
    func chartCardTrendBadgeUsesPercentagePoints() {
        let result = ChartCard.trendBadgeText(current: 13.0, baseline: 13.7, unit: "%", formatAsTime: false)
        #expect(result == "0.7 pts")
    }

    @Test("ChartCard trend badge uses minutes for time-based metrics")
    func chartCardTrendBadgeUsesMinutesForSleep() {
        let result = ChartCard.trendBadgeText(current: 6.65, baseline: 6.25, unit: "", formatAsTime: true)
        #expect(result == "24m")
    }

    @Test("Home card grid tokens use the 4pt spacing system")
    func homeCardGridTokens() {
        #expect(PerchTheme.HomeCard.horizontalPadding == 16)
        #expect(PerchTheme.HomeCard.verticalPadding == 16)
        #expect(PerchTheme.HomeCard.rowSpacing == 8)
        #expect(PerchTheme.HomeCard.columnGutter == 8)
        #expect(PerchTheme.HomeCard.trailingColumnMinWidth == 88)
    }

    @Test("Calendar today past label removes the redundant verb")
    func calendarTodayPastLabelUsesCompactCopy() {
        #expect(CalendarTodayCard.pastRelativeLabel(minutesAgo: 28) == "28m ago")
        #expect(CalendarTodayCard.pastRelativeLabel(minutesAgo: 121) == "done")
    }
}
