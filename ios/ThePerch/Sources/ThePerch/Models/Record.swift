import Foundation

// MARK: - Enums

/// The type of record (measurement, delivery, event, etc.).
enum RecordType: String, Codable, CaseIterable {
    case measurement
    case delivery
    case event
    case status
    case reminder
    case textNote = "text_note"
    case checklist
    case costSummary = "cost_summary"
    case bookmark

    var displayName: String {
        switch self {
        case .measurement:
            return "Measurement"
        case .delivery:
            return "Delivery"
        case .event:
            return "Event"
        case .status:
            return "Status"
        case .reminder:
            return "Reminder"
        case .textNote:
            return "Text Note"
        case .checklist:
            return "Checklist"
        case .costSummary:
            return "Cost Summary"
        case .bookmark:
            return "Bookmark"
        }
    }
}

/// The category a record belongs to (affects organization and filtering).
enum RecordCategory: String, Codable, CaseIterable {
    case health
    case deliveries
    case calendar
    case admin
    case legal
    case bookmarks

    var displayName: String {
        switch self {
        case .health:
            return "Health"
        case .deliveries:
            return "Deliveries"
        case .calendar:
            return "Calendar"
        case .admin:
            return "Admin"
        case .legal:
            return "Legal"
        case .bookmarks:
            return "Bookmarks"
        }
    }
}

/// Hint for how the record's data should be displayed.
enum DisplayHint: String, Codable, CaseIterable {
    case chart
    case singleValue = "single_value"
    case statusList = "status_list"
    case timeline
    case checklist
    case costBreakdown = "cost_breakdown"
    case bookmarkCard = "bookmark_card"
    case bookmarkGrid = "bookmark_grid"
    case progressGauge = "progress_gauge"
    case macrosBar = "macros_bar"

    var displayName: String {
        switch self {
        case .chart:
            return "Chart"
        case .singleValue:
            return "Single Value"
        case .statusList:
            return "Status List"
        case .timeline:
            return "Timeline"
        case .checklist:
            return "Checklist"
        case .costBreakdown:
            return "Cost Breakdown"
        case .bookmarkCard:
            return "Bookmark Card"
        case .bookmarkGrid:
            return "Bookmark Grid"
        case .progressGauge:
            return "Progress Gauge"
        case .macrosBar:
            return "Macros Bar"
        }
    }
}

/// Suggested card size for the record in UI.
enum CardSize: String, Codable {
    case small
    case medium
    case large
}

// MARK: - Record Model

/// A record is a unit of data captured by an OpenClaw agent.
/// It contains flexible JSON data, type and category information, and metadata.
struct Record: Identifiable, Codable, Equatable {
    let id: UUID
    let agentId: String
    let userId: UUID
    let type: RecordType
    let category: RecordCategory
    let title: String
    let data: JSONValue
    let displayHint: DisplayHint
    let annotations: JSONValue?
    var pinned: Bool
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case category
        case title
        case data
        case pinned
        case annotations
        case agentId = "agent_id"
        case userId = "user_id"
        case displayHint = "display_hint"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }

    /// Returns true if the record has expired based on the expiresAt date.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date.now > expiresAt
    }

    /// Returns the relative time string for the record (e.g., "2 hours ago").
    var relativeTime: String {
        let interval = Date.now.timeIntervalSince(createdAt)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 {
            return "now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else if days < 7 {
            return "\(days)d ago"
        } else {
            return PerchFormatters.mediumDate.string(from: createdAt)
        }
    }
}

// MARK: - Decoded Payload Cache

/// Caches decoded JSON payloads keyed by record ID + type name.
/// Avoids re-decoding the same record data on every view render.
final class DecodingCache {
    static let shared = DecodingCache()

    private let cache = NSCache<NSString, AnyObject>()

    private init() {
        cache.countLimit = 500
    }

    func get<T>(_ recordId: UUID, as type: T.Type) -> T? {
        let key = "\(recordId)-\(String(describing: type))" as NSString
        return (cache.object(forKey: key) as? Box<T>)?.value
    }

    func set<T>(_ value: T, for recordId: UUID, as type: T.Type) {
        let key = "\(recordId)-\(String(describing: type))" as NSString
        cache.setObject(Box(value), forKey: key)
    }

    /// Clear all cached payloads (call on refresh).
    func clear() {
        cache.removeAllObjects()
    }

    /// Type-erased wrapper for storing value types in NSCache.
    private class Box<T>: NSObject {
        let value: T
        init(_ value: T) { self.value = value }
    }
}

// MARK: - Record Extension for Type-Safe Data Decoding

extension Record {
    /// Shared encoder/decoder — avoids recreating on each call.
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Attempts to decode the record's flexible JSON `data` field into a specific typed struct.
    /// Results are cached by record ID + type to avoid redundant decoding.
    func decodeData<T: Decodable>(as type: T.Type) -> T? {
        // Check cache first
        if let cached: T = DecodingCache.shared.get(id, as: type) {
            return cached
        }
        // Decode and cache
        guard let jsonData = try? Self.jsonEncoder.encode(data),
              let decoded = try? Self.jsonDecoder.decode(T.self, from: jsonData) else { return nil }
        DecodingCache.shared.set(decoded, for: id, as: type)
        return decoded
    }
}
