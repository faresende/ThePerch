import Foundation

/// One agent-generated insight. Backed by `public.insights`. See spec:
/// `docs/superpowers/specs/2026-04-26-insights-and-health-integrations-design.md`.
///
/// The Today tab queries for today's `daily_health` insight (BioChecha)
/// and renders it in a `DailyInsightCard`. Other insight types
/// (`cross_domain`, `spending_pattern`, `anomaly`, `negative_space`,
/// `latency`) will surface elsewhere in the app as they're implemented.
struct Insight: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let userId: UUID
    let agentId: String
    let insightType: String
    let title: String?
    let body: String
    let data: AnyJSON?
    let sourceRefs: AnyJSON?
    let generatedAt: Date
    let validForDate: Date?
    let shownAt: Date?
    let dismissedAt: Date?
    let pinned: Bool
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case agentId = "agent_id"
        case insightType = "insight_type"
        case title
        case body
        case data
        case sourceRefs = "source_refs"
        case generatedAt = "generated_at"
        case validForDate = "valid_for_date"
        case shownAt = "shown_at"
        case dismissedAt = "dismissed_at"
        case pinned
        case expiresAt = "expires_at"
    }

    /// Convenience: known insight types iOS knows how to render. Falls
    /// back to plain card display when an unknown type comes back.
    enum Kind: String, Sendable {
        case dailyHealth = "daily_health"
        case crossDomain = "cross_domain"
        case spendingPattern = "spending_pattern"
        case anomaly = "anomaly"
        case negativeSpace = "negative_space"
        case latency = "latency"
        case unknown
    }

    var kind: Kind {
        Kind(rawValue: insightType) ?? .unknown
    }

    /// Display kicker: "TODAY · BIOCHECHA" / "ANOMALY · BIOCHECHA" / etc.
    var kicker: String {
        let prefix: String
        switch kind {
        case .dailyHealth:    prefix = "TODAY"
        case .crossDomain:    prefix = "PATTERN"
        case .spendingPattern: prefix = "SPENDING"
        case .anomaly:        prefix = "WORTH NOTING"
        case .negativeSpace:  prefix = "WORTH A CHECK"
        case .latency:        prefix = "RUNNING LATE"
        case .unknown:        prefix = "INSIGHT"
        }
        return "\(prefix) · \(agentId.uppercased())"
    }
}

/// Minimal AnyJSON wrapper so Insight can decode the polymorphic
/// `data` and `source_refs` columns without forcing every consumer to
/// know the shape. Stored as raw bytes; specific consumers can decode
/// into typed structs when needed.
struct AnyJSON: Codable, Sendable, Equatable {
    let raw: Data

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // The PostgREST/JSONSerialization round-trip can hand us any
        // shape (object, array, primitive) — re-encode so callers can
        // re-parse on demand.
        if let dict = try? container.decode([String: AnyCodableValue].self) {
            self.raw = (try? JSONEncoder().encode(dict)) ?? Data()
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            self.raw = (try? JSONEncoder().encode(arr)) ?? Data()
        } else {
            self.raw = Data()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

/// Type-erased codable for AnyJSON's intermediate parsing pass.
private enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: AnyCodableValue].self) { self = .object(v) }
        else if let v = try? c.decode([AnyCodableValue].self) { self = .array(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        }
    }
}
