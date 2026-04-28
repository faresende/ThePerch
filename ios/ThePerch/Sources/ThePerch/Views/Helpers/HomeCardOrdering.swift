import Foundation

/// Determines which home cards to show and in what order.
///
/// Previous version varied the order by time-of-day. The user found
/// that confusing — a stable order is more useful as a daily reference
/// than a smart-but-shifting one. Single canonical order now,
/// regardless of time of day:
///
///   BioChecha (rendered separately at top of TodayTab)
///   1. Nutrition
///   2. Calendar (today)
///   3. Orders (deliveries)
///   4. Calendar (tomorrow)
///   5. Health (with sleep graph)
///
/// Medications / Weather / Email summary were dropped — they didn't
/// earn their place on the daily-front-page surface.
enum HomeCardType: CaseIterable, Hashable {
    case nutrition
    case calendarToday
    case deliveries
    case calendarTomorrow
    case healthSummary
}

enum HomeCardOrdering {
    /// Time-of-day buckets. Kept as a public type because other
    /// surfaces (e.g. AmbienceManager) reuse it to drive non-card
    /// behaviour (palette tinting). Card ordering itself no longer
    /// switches on this — see `orderedCards()`.
    enum TimePeriod {
        case morning    // 06:00–11:59
        case afternoon  // 12:00–16:59
        case evening    // 17:00–21:59
        case night      // 22:00–05:59

        static var current: TimePeriod {
            let hour = Calendar.current.component(.hour, from: Date.now)
            switch hour {
            case 6..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<22: return .evening
            default: return .night
            }
        }
    }

    /// Returns the canonical card order. Stable across times of day.
    static func orderedCards() -> [HomeCardType] {
        [.nutrition, .calendarToday, .deliveries, .calendarTomorrow, .healthSummary]
    }

    /// Health card always renders in its full form (with the sleep
    /// graph) — no time-of-day compacting.
    static func isHealthCompact() -> Bool { false }
}
