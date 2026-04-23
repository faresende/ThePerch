import Foundation

/// A review item surfaced by the orders-autopilot classifier when an email
/// looks order-relevant but couldn't be confidently matched to an order (or
/// a tracking number couldn't be extracted). Users resolve these in the
/// Review Items sheet via OrdersView.
///
/// Shape mirrors the `public.review_items` table:
///   id, user_id, type, related_order_id, related_shipment_id,
///   reason, suggested_action, confidence_score,
///   resolved_at, created_at, updated_at
///
/// `resolved_at = nil` means "needs attention". Writing a timestamp soft-
/// dismisses the item; we never hard-delete so audit trails stay intact.
struct ReviewItem: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: UUID
    let userId: UUID
    let type: String                  // 'orphan_shipment' | 'shipment_no_order' | future kinds
    let relatedOrderId: UUID?
    let relatedShipmentId: UUID?
    let reason: String
    let suggestedAction: String?
    let confidenceScore: Double
    let resolvedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    var isResolved: Bool { resolvedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case relatedOrderId = "related_order_id"
        case relatedShipmentId = "related_shipment_id"
        case reason
        case suggestedAction = "suggested_action"
        case confidenceScore = "confidence_score"
        case resolvedAt = "resolved_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Human-readable kind for the UI.
    var displayKind: String {
        switch type {
        case "orphan_shipment":    return "No tracking number"
        case "shipment_no_order":  return "Unmatched shipment"
        default:                    return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Pick a reasonable icon for each known kind.
    var systemImage: String {
        switch type {
        case "orphan_shipment":    return "questionmark.app.dashed"
        case "shipment_no_order":  return "link.badge.plus"
        default:                    return "exclamationmark.triangle"
        }
    }
}
