import Foundation

/// Determines which home cards to show and in what order, based on current time of day.
/// See HOME_REDESIGN.md Part 1.2 for the full priority specification.
enum HomeCardType: CaseIterable, Hashable {
    case dailyBriefing
    case workoutHint
    case healthSummary
    case calendarToday
    case calendarTomorrow
    case nutrition
    case deliveries
    case medications
    case weather
    case emailSummary
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
        // Daily briefing + workout hint always sit at the very top when
        // they're present. The card's own empty-state prevents visual
        // clutter on days BioChecha hasn't written one yet.
        let preamble: [HomeCardType] = [.dailyBriefing, .workoutHint]
        switch period {
        case .morning:
            return preamble + [.healthSummary, .medications, .calendarToday, .weather, .deliveries, .nutrition, .calendarTomorrow, .emailSummary]
        case .afternoon:
            return preamble + [.calendarToday, .nutrition, .deliveries, .healthSummary, .emailSummary]
        case .evening:
            return preamble + [.nutrition, .calendarTomorrow, .deliveries, .healthSummary]
        case .night:
            return preamble + [.calendarTomorrow, .healthSummary, .nutrition]
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
