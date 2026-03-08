import Foundation

/// Centralized static formatters to avoid recreating them on every render.
/// DateFormatter and NumberFormatter are expensive to create — these are reused.
enum PerchFormatters {
    // MARK: - Date Formatters

    /// "Mar 8" — short month + day
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "14:30" — 24-hour time
    static let time24h: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "2:30 PM" — 12-hour time with AM/PM
    static let time12h: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// "yyyy-MM-dd" — ISO date string for matching/comparison
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    /// "Monday, Mar 8" — weekday + month + day
    static let weekdayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    /// Medium date style (system locale) — e.g., "Mar 8, 2026"
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Medium date + short time — e.g., "Mar 8, 2026 at 2:30 PM"
    static let mediumDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Weekday name only — e.g., "Monday"
    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    /// "Mar 8, 2:30 PM" — short date + time for event summaries
    static let eventDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    /// "Sun Mar 8" — short weekday + month + day
    static let shortWeekdayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    /// ISO 8601 formatter
    static let iso8601: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    // MARK: - Number Formatters

    /// Decimal with up to 2 fraction digits — "1,234.56"
    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }()

    /// Percent — "85%"
    static let percent: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 0
        return f
    }()
}
