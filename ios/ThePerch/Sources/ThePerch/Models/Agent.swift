import Foundation

/// Represents an OpenClaw agent that generates records.
struct Agent: Identifiable, Codable, Equatable {
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

    private var lookupKey: String {
        "\(id) \(displayName)".lowercased()
    }

    var roleLabel: String {
        switch lookupKey {
        case let key where key.contains("claudinho"):
            return "Assistant"
        case let key where key.contains("biochecha"):
            return "Health"
        case let key where key.contains("healthkit") || key.contains("apple health"):
            return "Apple Health"
        case let key where key.contains("entregas") || key.contains("delivery"):
            return "Deliveries"
        case let key where key.contains("calendario") || key.contains("calendar"):
            return "Calendar"
        case let key where key.contains("archie"):
            return "Knowledge"
        case let key where key.contains("legal"):
            return "Legal"
        default:
            return "Agent"
        }
    }

    var roleDescription: String {
        switch lookupKey {
        case let key where key.contains("claudinho"):
            return "General assistant and gateway orchestrator"
        case let key where key.contains("biochecha"):
            return "Health insights and medication support"
        case let key where key.contains("healthkit") || key.contains("apple health"):
            return "Syncs Apple Health data into ThePerch"
        case let key where key.contains("entregas") || key.contains("delivery"):
            return "Tracks deliveries and package updates"
        case let key where key.contains("calendario") || key.contains("calendar"):
            return "Keeps calendar events and reminders in sync"
        case let key where key.contains("archie"):
            return "Organizes bookmarks, notes, and saved knowledge"
        case let key where key.contains("legal"):
            return "Handles legal research and document support"
        default:
            return "AI agent for background automations"
        }
    }

    var subtitleLine: String {
        if let model, !model.isEmpty {
            return "\(roleDescription) · \(model)"
        }
        return roleDescription
    }

    var disambiguationLabel: String {
        if roleLabel != "Agent" {
            return roleLabel
        }
        if let model, !model.isEmpty {
            return model
        }
        return id
    }
}

enum AgentIdentity {
    /// Per-agent emoji fallback when the DB row's `emoji` column is
    /// nil/empty. Internal agent IDs are project-level — the canonical
    /// names (`biochecha`, `calendario`, `entregas`, etc.) are kept as
    /// stable identifiers because they're referenced throughout the
    /// Python ingest layer.
    static func emoji(for agentId: String) -> String {
        switch agentId {
        case "main", "claudinho":  return "🤖"
        case "biochecha":          return "💊"
        case "entregas":           return "📦"
        case "calendario":         return "📅"
        case "legal":              return "⚖️"
        case "archie":             return "📚"
        case "calendar-sync":      return "📅"
        case "delivery-tracker":   return "🚚"
        case "healthkit":          return "❤️"
        case "nutrition-aggregator", "orders-autopilot", "orders-ingest-catchup":
            return "⚙️"
        default: return "⚙️"
        }
    }

    /// Last-resort display-name fallback. Always prefer the DB row's
    /// `display_name` when available — this map only fires when the
    /// app sees an agent_id with no DB row (e.g. mock data) or when
    /// the DB row has no display_name set. Mappings here intentionally
    /// give the historical agent IDs neutral, generic display names.
    static func name(for agentId: String) -> String {
        switch agentId {
        case "main", "claudinho":  return "Main"
        case "biochecha":          return "Health"
        case "entregas":           return "Orders"
        case "calendario":         return "Calendar"
        case "legal":              return "Legal"
        case "archie":             return "Archive"
        case "calendar-sync":      return "Calendar Sync"
        case "delivery-tracker":   return "Delivery Tracker"
        case "healthkit":          return "Apple Health"
        case "nutrition-aggregator": return "Nutrition Aggregator"
        case "orders-autopilot":     return "Orders Autopilot"
        case "orders-ingest-catchup": return "Orders Catchup"
        default: return agentId.capitalized
        }
    }
}
