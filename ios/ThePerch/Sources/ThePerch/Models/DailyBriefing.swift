import Foundation

/// Payload for a `daily_briefing` record — BioChecha's morning summary,
/// surfaced as a card at the top of the Today tab.
///
/// Contract documented in
/// `docs/superpowers/specs/2026-04-23-biochecha-daily-surfaces.md`.
/// All fields except `date` and `generated_at` are optional; the iOS
/// card renders what's present and hides the rest.
struct DailyBriefingData: Codable, Sendable {
    let date: String
    let headline: String?
    let highlights: [Highlight]?
    let actionItems: [ActionItem]?
    let recoveryRating: RecoveryRating?
    let generatedAt: Date

    enum RecoveryRating: String, Codable, Sendable {
        case green, yellow, red
    }

    struct Highlight: Codable, Sendable, Identifiable {
        var id: String { "\(icon ?? "")-\(label)" }
        let icon: String?
        let label: String
        let trend: Trend?
        let detail: String?

        enum Trend: String, Codable, Sendable {
            case up, down, steady
        }
    }

    struct ActionItem: Codable, Sendable, Identifiable {
        var id: String { text }
        let text: String
        let priority: Priority?

        enum Priority: String, Codable, Sendable {
            case high, medium, low
        }
    }

    enum CodingKeys: String, CodingKey {
        case date, headline, highlights
        case actionItems = "action_items"
        case recoveryRating = "recovery_rating"
        case generatedAt = "generated_at"
    }
}

/// Payload for a `workout_hint` record — BioChecha's suggested next
/// workout type (pull/push/legs/rest) based on last-7-days history.
struct WorkoutHintData: Codable, Sendable {
    let date: String
    let suggestedType: SuggestedType
    let reasoning: String?
    let last7d: Last7d?
    let flags: [Flag]?
    let generatedAt: Date

    enum SuggestedType: String, Codable, Sendable {
        case pull, push, legs, rest, mixed, other

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = SuggestedType(rawValue: raw.lowercased()) ?? .other
        }
    }

    struct Last7d: Codable, Sendable {
        let pull: Bucket?
        let push: Bucket?
        let legs: Bucket?
        let rest: Bucket?

        struct Bucket: Codable, Sendable {
            let count: Int
            let lastDate: String?

            enum CodingKeys: String, CodingKey {
                case count
                case lastDate = "last_date"
            }
        }
    }

    struct Flag: Codable, Sendable, Identifiable {
        var id: String { "\(kind):\(detail.prefix(40))" }
        let kind: String       // muscle_gap | volume_trend | overtraining | pr_adjacent | custom
        let detail: String
    }

    enum CodingKeys: String, CodingKey {
        case date, reasoning, flags
        case suggestedType = "suggested_type"
        case last7d = "last_7d"
        case generatedAt = "generated_at"
    }
}
