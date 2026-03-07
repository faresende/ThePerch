import Foundation

/// Represents a section of the dashboard, typically corresponding to a RecordCategory.
struct Section: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let slug: String
    let displayName: String
    var sortOrder: Int
    var isVisible: Bool
    let config: JSONValue?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case displayName = "display_name"
        case sortOrder = "sort_order"
        case isVisible = "is_visible"
        case config
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
    }

    /// Returns the category associated with this section's slug, if applicable.
    var category: RecordCategory? {
        RecordCategory(rawValue: slug)
    }
}

/// Represents a widget configuration for the home dashboard.
struct HomeWidget: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let position: Int
    let widgetType: String
    let config: JSONValue?
    let isVisible: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case position
        case widgetType = "widget_type"
        case config
        case isVisible = "is_visible"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
    }
}
