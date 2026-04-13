import Foundation

struct Order: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let merchant: String
    let orderNumber: String
    let total: Decimal?
    let currency: String
    let status: String
    let sourceEmailId: String
    let confidence: Double
    let createdAt: Date
    /// Set by the user to mark an order delivered when automated tracking cannot confirm it.
    /// `nil` means automated tracking controls status. Never written by automated agents.
    let manualDeliveredAt: Date?

    /// True when the user has manually overridden this order's status to delivered.
    var isManuallyDelivered: Bool { manualDeliveredAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case merchant
        case orderNumber = "order_number"
        case total
        case currency
        case status
        case sourceEmailId = "source_email_id"
        case confidence
        case createdAt = "created_at"
        case manualDeliveredAt = "manual_delivered_at"
    }
}

struct Shipment: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let orderId: UUID
    let trackingNumber: String
    let carrier: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case trackingNumber = "tracking_number"
        case carrier
        case status
        case createdAt = "created_at"
    }
}

struct OrderWithShipments: Identifiable, Sendable, Equatable {
    let order: Order
    let shipments: [Shipment]

    var id: UUID { order.id }

    var primaryShipment: Shipment? {
        shipments.sorted { $0.createdAt > $1.createdAt }.first
    }

    var displayStatus: String {
        primaryShipment?.status ?? order.status
    }

    /// Status that respects manual delivery overrides.
    /// If the user has manually marked the order delivered, this always returns "delivered"
    /// regardless of what automated tracking or the `status` column say.
    var effectiveStatus: String {
        if order.isManuallyDelivered { return "delivered" }
        return primaryShipment?.status ?? order.status
    }
}
