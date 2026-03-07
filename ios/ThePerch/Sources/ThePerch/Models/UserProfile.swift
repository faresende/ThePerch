import Foundation

/// Represents a user's profile and preferences.
struct UserProfile: Identifiable, Codable {
    let id: UUID
    let email: String
    let displayName: String
    let avatar: String?
    let preferences: UserPreferences?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatar
        case preferences
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// User-specific preferences and settings.
struct UserPreferences: Codable {
    let theme: String?
    let notificationsEnabled: Bool?
    let defaultCardSize: String?
    let language: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case theme
        case notificationsEnabled = "notifications_enabled"
        case defaultCardSize = "default_card_size"
        case language
        case timezone
    }

    init(
        theme: String? = nil,
        notificationsEnabled: Bool? = nil,
        defaultCardSize: String? = nil,
        language: String? = nil,
        timezone: String? = nil
    ) {
        self.theme = theme
        self.notificationsEnabled = notificationsEnabled
        self.defaultCardSize = defaultCardSize
        self.language = language
        self.timezone = timezone
    }
}
