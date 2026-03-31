import Foundation

// MARK: - Enums

/// The type of record (measurement, delivery, event, etc.).
enum RecordType: String, Codable, CaseIterable, Sendable {
    case measurement
    case meal
    case delivery
    case event
    case status
    case reminder
    case textNote = "text_note"
    case checklist
    case costSummary = "cost_summary"
    case bookmark
    case command
    case trip
    case itinerary
    case travelAlert = "travel_alert"
    case weatherForecast = "weather_forecast"
    case travelTask = "travel_task"
    case workoutSession = "workout_session"
    case calendarEvent = "calendar_event"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = RecordType(rawValue: rawValue) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .measurement:
            return "Measurement"
        case .meal:
            return "Meal"
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
        case .command:
            return "Command"
        case .trip:
            return "Trip"
        case .itinerary:
            return "Itinerary"
        case .travelAlert:
            return "Travel Alert"
        case .weatherForecast:
            return "Weather Forecast"
        case .travelTask:
            return "Travel Task"
        case .workoutSession:
            return "Workout Session"
        case .calendarEvent:
            return "Calendar Event"
        case .unknown:
            return "Unknown"
        }
    }
}

/// The category a record belongs to (affects organization and filtering).
enum RecordCategory: String, Codable, CaseIterable, Sendable {
    case health
    case nutrition
    case workouts
    case deliveries
    case calendar
    case admin
    case legal
    case bookmarks
    case travel
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = RecordCategory(rawValue: rawValue) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .health:
            return "Health"
        case .nutrition:
            return "Nutrition"
        case .workouts:
            return "Workouts"
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
        case .travel:
            return "Travel"
        case .unknown:
            return "Unknown"
        }
    }
}

/// Hint for how the record's data should be displayed.
enum DisplayHint: String, Codable, CaseIterable, Sendable {
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
    case calendarEvent = "calendar_event"
    case mealLog = "meal_log"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = DisplayHint(rawValue: rawValue) ?? .unknown
    }

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
        case .calendarEvent:
            return "Calendar Event"
        case .mealLog:
            return "Meal Log"
        case .unknown:
            return "Unknown"
        }
    }
}

/// Suggested card size for the record in UI.
enum CardSize: String, Codable, Sendable {
    case small
    case medium
    case large
}

// MARK: - Record Model

/// A record is a unit of data captured by an OpenClaw agent.
/// It contains flexible JSON data, type and category information, and metadata.
struct Record: Identifiable, Codable, Equatable, Sendable {
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
        createdAt.relativeTime
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
    /// Attempts to decode the record's flexible JSON `data` field into a specific typed struct.
    /// Uses JSONValueDecoder to walk the JSONValue enum tree directly (no encode→Data round-trip).
    /// Results are cached by record ID + type to avoid redundant decoding.
    func decodeData<T: Decodable>(as type: T.Type) -> T? {
        // Check cache first
        if let cached: T = DecodingCache.shared.get(id, as: type) {
            return cached
        }
        // Decode directly from JSONValue tree (skips encode→Data→decode round-trip)
        guard let decoded = JSONValueDecoder.decode(type, from: data) else { return nil }
        DecodingCache.shared.set(decoded, for: id, as: type)
        return decoded
    }
}
