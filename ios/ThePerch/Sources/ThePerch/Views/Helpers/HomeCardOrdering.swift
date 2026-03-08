import Foundation

/// Determines which home cards to show and in what order, based on current time of day.
/// See HOME_REDESIGN.md Part 1.2 for the full priority specification.
enum HomeCardType: CaseIterable, Hashable {
    case healthSummary
    case calendarToday
    case calendarTomorrow
    case nutrition
    case deliveries
}

enum HomeCardOrdering {
    /// Current time-of-day period.
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

    /// Returns the ordered list of card types for the current time of day.
    static func orderedCards(for period: TimePeriod = .current) -> [HomeCardType] {
        switch period {
        case .morning:
            return [.healthSummary, .calendarToday, .deliveries, .nutrition, .calendarTomorrow]
        case .afternoon:
            return [.calendarToday, .nutrition, .deliveries, .healthSummary]
        case .evening:
            return [.nutrition, .calendarTomorrow, .deliveries, .healthSummary]
        case .night:
            return [.calendarTomorrow, .healthSummary, .nutrition]
        }
    }

    /// Whether the health card should be shown in compact mode.
    static func isHealthCompact(for period: TimePeriod = .current) -> Bool {
        switch period {
        case .morning: return false
        case .afternoon, .evening, .night: return true
        }
    }
}
