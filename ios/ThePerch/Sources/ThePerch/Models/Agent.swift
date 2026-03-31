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
    static func emoji(for agentId: String) -> String {
        switch agentId {
        case "claudinho": return "🤖"
        case "biochecha": return "💊"
        case "entregas": return "📦"
        case "calendario": return "📅"
        case "legal": return "⚖️"
        case "archie": return "📚"
        default: return "⚙️"
        }
    }

    static func name(for agentId: String) -> String {
        switch agentId {
        case "claudinho": return "Claudinho"
        case "biochecha": return "BioChecha"
        case "entregas": return "Entregas"
        case "calendario": return "Calendario"
        case "legal": return "Legal"
        case "archie": return "Archie"
        default: return agentId.capitalized
        }
    }
}
