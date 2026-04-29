import Foundation

/// Centralized static formatters to avoid recreating them on every render.
/// DateFormatter and NumberFormatter are expensive to create — these are reused.
///
/// `nonisolated` because the project's default actor-isolation is
/// MainActor — but these formatters are accessed from off-main paths
/// (decode helpers in `DataPayloads.swift`, `Task.detached` predecode,
/// etc.). Foundation's date/number formatters are documented
/// thread-safe.
nonisolated enum PerchFormatters {
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

    /// "M", "T", "W" — single-letter day abbreviation.
    static let dayLetter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    /// "SUN · MAR 8" — agenda kicker style (fixed en_GB format, uppercased
    /// at call site when needed). Used on the Hub Calendar section and
    /// other UK-style kickers.
    static let agendaKicker: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE · MMM d"
        return f
    }()

    /// "Mon" — short weekday only (en_GB).
    static let shortWeekdayUK: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE"
        return f
    }()

    /// "Mar 8" (en_GB) — used by travel/order aside labels.
    static let shortDateUK: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "MMM d"
        return f
    }()

    /// "TODAY · MAR 8" — literal TODAY + month + day (en_GB), uppercased
    /// at call site.
    static let todayKicker: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "'TODAY' · MMM d"
        return f
    }()

    /// "h:mm am/pm" (en_GB, lowercase am/pm) — health-freshness label.
    static let healthFreshness: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "h:mm a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    /// "Tue, 7 Apr" — calendar-card eyebrow (en_GB), uppercased at call site.
    static let cardEyebrowDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE, d MMM"
        return f
    }()

    /// ISO 8601 formatter (no fractional seconds).
    static let iso8601: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    /// ISO 8601 formatter with fractional seconds. Some PostgREST
    /// timestamps include them, some don't — try this one first, then
    /// fall back to `iso8601`.
    static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Relative date/time — "2 min. ago", "3 hr. ago"
    static let relativeDateTime: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
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

    /// Plain integer formatter ("1,234") — for body kcal / step counts /
    /// review item totals. R12 audit caught half a dozen call sites
    /// constructing a fresh NumberFormatter per body render.
    static let integer: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    // MARK: - Currency Cache
    //
    // Currency formatters are heavier than DateFormatters (~50–150µs per
    // init: locale lookup + currency-symbol resolution). 6+ call sites
    // were creating one per body render, costing 0.5–2ms of avoidable
    // main-actor work per re-render. R12 fix: cache by (currency code,
    // fraction digits). NSCache isn't needed — total currency codes used
    // by the app is small and bounded; a plain dict on a serial queue
    // is fine for read-mostly access.

    private static let currencyLock = NSLock()
    nonisolated(unsafe) private static var currencyCache: [String: NumberFormatter] = [:]

    /// Returns a cached `NumberFormatter` configured for `code` (an ISO
    /// 4217 currency code, e.g. "EUR", "USD"). Defaults to 2 fraction
    /// digits — pass 0 for whole-currency contexts. Foundation's
    /// NumberFormatter is documented thread-safe for read access; mutation
    /// (setCurrencyCode etc.) is what's not safe, so we lock at insert.
    static func currency(code: String, fractionDigits: Int = 2) -> NumberFormatter {
        let key = "\(code)|\(fractionDigits)"
        currencyLock.lock()
        defer { currencyLock.unlock() }
        if let cached = currencyCache[key] { return cached }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = fractionDigits
        currencyCache[key] = f
        return f
    }

    // MARK: - Helpers

    static func uptimeString(from hours: Double) -> String {
        let days = Int(hours / 24)
        let remainingHours = Int(hours) % 24

        if days > 0 {
            return "\(days)d \(remainingHours)h"
        }

        return "\(Int(hours))h"
    }
}

extension Date {
    var relativeTime: String {
        let interval = Date.now.timeIntervalSince(self)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 0 {
            let absoluteMinutes = abs(minutes)
            let absoluteHours = abs(hours)

            if absoluteMinutes < 60 {
                return "in \(absoluteMinutes)m"
            }

            if absoluteHours < 24 {
                return "in \(absoluteHours)h \(absoluteMinutes % 60)m"
            }

            return "in \(abs(days))d"
        }

        if minutes < 1 {
            return "now"
        }

        if minutes < 60 {
            return "\(minutes)m ago"
        }

        if hours < 24 {
            return "\(hours)h ago"
        }

        if days < 7 {
            return "\(days)d ago"
        }

        return PerchFormatters.mediumDate.string(from: self)
    }
}
