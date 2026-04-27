import Foundation

/// Phase 1 ETA copy formatter. Given a delivery date, return the
/// chip text the OrderCardV2 / OrderCard will render:
///
///   Future:
///     today           "Arrives today"
///     tomorrow        "Arrives tomorrow"
///     2-6 days out    "Arrives Tuesday"
///     7+ days         "Arrives May 5"
///
///   Past (no delivered event):
///     today (slipped) "Arrives today"   ← same calendar day = same day from user's POV
///     yesterday       "Was due yesterday"
///     2-6 days back   "Was due Tuesday"
///     7+ days back    "Was due May 5"
///
/// Locale-aware: weekday and month names follow Calendar.autoupdating
/// Current. Today special-cased so "Arrives today" stays calm even
/// when the ETA is technically slightly past — same calendar day is
/// the same day from the user's POV.
///
/// Spec: docs/superpowers/specs/2026-04-27-orders-eta-design.md.

enum ETAChipText {
    static func text(for date: Date, now: Date = .now) -> String {
        let cal = Calendar.autoupdatingCurrent
        let etaDay = cal.startOfDay(for: date)
        let today = cal.startOfDay(for: now)

        // dayDifference: positive = future, negative = past, 0 = today
        let dayDiff = cal.dateComponents([.day], from: today, to: etaDay).day ?? 0

        if dayDiff == 0 {
            return "Arrives today"
        }

        if dayDiff > 0 {
            // Future
            switch dayDiff {
            case 1:
                return "Arrives tomorrow"
            case 2...6:
                return "Arrives \(weekdayName(date))"
            default:
                return "Arrives \(monthDay(date))"
            }
        } else {
            // Past — non-delivered ETA
            switch -dayDiff {
            case 1:
                return "Was due yesterday"
            case 2...6:
                return "Was due \(weekdayName(date))"
            default:
                return "Was due \(monthDay(date))"
            }
        }
    }

    /// Whether the given date represents a past-due ETA (older than
    /// today). Used by views to choose the muted-vs-quietly-muted color
    /// treatment.
    static func isPastDue(_ date: Date, now: Date = .now) -> Bool {
        let cal = Calendar.autoupdatingCurrent
        return cal.startOfDay(for: date) < cal.startOfDay(for: now)
    }

    // MARK: - Formatters

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = .autoupdatingCurrent
        f.dateFormat = "EEEE"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = .autoupdatingCurrent
        // "MMM d" gives "May 5" in EN, "5 mai" in FR via locale-aware
        // template substitution.
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    private static func weekdayName(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    private static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }
}
