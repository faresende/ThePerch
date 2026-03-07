import Foundation

/// Represents an OpenClaw agent that generates records.
struct Agent: Identifiable, Codable {
    let id: String
    let displayName: String
    let emoji: String?
    let model: String?
    let isActive: Bool
    let lastHeartbeat: Date?
    let ownerId: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case emoji
        case model
        case isActive = "is_active"
        case lastHeartbeat = "last_heartbeat"
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }

    /// Returns true if the agent has reported a heartbeat within the last hour.
    var isHealthy: Bool {
        guard let lastHeartbeat else { return false }
        return Date.now.timeIntervalSince(lastHeartbeat) < 3600
    }

    /// Returns a display string combining emoji and name.
    var displayLabel: String {
        if let emoji {
            return "\(emoji) \(displayName)"
        }
        return displayName
    }
}
