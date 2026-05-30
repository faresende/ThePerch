import Foundation

struct Order: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let merchant: String
    let orderNumber: String
    let total: Decimal?
    let currency: String
    let status: String
    let confidence: Double
    let createdAt: Date
    /// Set by the user to mark an order delivered when automated tracking cannot confirm it.
    /// `nil` means automated tracking controls status. Never written by automated agents.
    let manualDeliveredAt: Date?
    /// Set when the user swipes "Not an order" via OrdersService.recordCorrection.
    /// Coupled with status='dismissed_by_user'. Reversed by cancelCorrection.
    /// Phase-1 corrections-and-rules (2026-04-27).
    let dismissedAt: Date?
    /// True when this order is digital/non-package noise filtered out of the
    /// surfaced zones. Stamped server-side (`orders.hidden`, NOT NULL default
    /// false); the default fetch excludes these. Drives the Hidden zone.
    let hidden: Bool
    /// Server-side label for the kind of order (e.g. "physical"). Only stamped
    /// on NEW orders going forward — NULL on all existing rows — so it is NOT
    /// used to derive zones. Carried through for future use only.
    let classification: String?

    /// True when the user has manually overridden this order's status to delivered.
    var isManuallyDelivered: Bool { manualDeliveredAt != nil }
    /// True when the user dismissed this row via "Not an order" swipe.
    /// `OrdersService` filters these from default Today/Active queries.
    var isDismissedByUser: Bool { status == "dismissed_by_user" }
    /// True when the parser flagged this as a digital purchase (no shipment expected).
    var isDigital: Bool { status == "digital" }

    // Columns were renamed during the Apr 2026 orders-schema cleanup:
    //   merchant          → merchant_name
    //   total             → total_amount
    //   confidence        → confidence_score
    //   source_email_id   → source_email_ids (array, now read by backend only)
    // The Swift property names are kept stable so views don't change.
    enum CodingKeys: String, CodingKey {
        case id
        case merchant = "merchant_name"
        case orderNumber = "order_number"
        case total = "total_amount"
        case currency
        case status
        case confidence = "confidence_score"
        case createdAt = "created_at"
        case manualDeliveredAt = "manual_delivered_at"
        case dismissedAt = "dismissed_at"
        case hidden
        case classification
    }

    /// Memberwise initializer with `dismissedAt` defaulted so previews
    /// and test fixtures compiled before the corrections-and-rules
    /// migration keep working without the new parameter.
    init(
        id: UUID,
        merchant: String,
        orderNumber: String,
        total: Decimal?,
        currency: String,
        status: String,
        confidence: Double,
        createdAt: Date,
        manualDeliveredAt: Date? = nil,
        dismissedAt: Date? = nil,
        hidden: Bool = false,
        classification: String? = nil
    ) {
        self.id = id
        self.merchant = merchant
        self.orderNumber = orderNumber
        self.total = total
        self.currency = currency
        self.status = status
        self.confidence = confidence
        self.createdAt = createdAt
        self.manualDeliveredAt = manualDeliveredAt
        self.dismissedAt = dismissedAt
        self.hidden = hidden
        self.classification = classification
    }
}

// Custom decoding lives in an extension so the synthesized memberwise
// initializer on Order stays available for previews and test fixtures.
extension Order {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let merchant = (try c.decodeIfPresent(String.self, forKey: .merchant)) ?? "Unknown merchant"
        let orderNumber = (try c.decodeIfPresent(String.self, forKey: .orderNumber)) ?? ""
        let total = try c.decodeIfPresent(Decimal.self, forKey: .total)
        let currency = (try c.decodeIfPresent(String.self, forKey: .currency)) ?? ""
        let status = (try c.decodeIfPresent(String.self, forKey: .status)) ?? "unknown"
        let confidence = (try c.decodeIfPresent(Double.self, forKey: .confidence)) ?? 0
        let createdAt = try c.decode(Date.self, forKey: .createdAt)
        let manualDeliveredAt = try c.decodeIfPresent(Date.self, forKey: .manualDeliveredAt)
        let dismissedAt = try c.decodeIfPresent(Date.self, forKey: .dismissedAt)
        let hidden = (try c.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
        let classification = try c.decodeIfPresent(String.self, forKey: .classification)
        self.init(
            id: id,
            merchant: merchant,
            orderNumber: orderNumber,
            total: total,
            currency: currency,
            status: status,
            confidence: confidence,
            createdAt: createdAt,
            manualDeliveredAt: manualDeliveredAt,
            dismissedAt: dismissedAt,
            hidden: hidden,
            classification: classification
        )
    }
}

struct Shipment: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let orderId: UUID
    let trackingNumber: String
    let carrier: String
    let status: String
    let createdAt: Date
    let trackingUrl: String?
    /// Phase 1 ETA (2026-04-27): expected delivery date for this
    /// shipment. Set by carrier-email regex extraction or 17track
    /// polling, resolved server-side via resolveETAUpdate (priority +
    /// recency). NULL for legacy rows / shipments without an ETA.
    /// `eta_source` and `eta_recorded_at` aren't surfaced in iOS —
    /// scanner-side bookkeeping only.
    let etaAt: Date?

    init(
        id: UUID,
        orderId: UUID,
        trackingNumber: String,
        carrier: String,
        status: String,
        createdAt: Date,
        trackingUrl: String? = nil,
        etaAt: Date? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.trackingNumber = trackingNumber
        self.carrier = carrier
        self.status = status
        self.createdAt = createdAt
        self.trackingUrl = trackingUrl
        self.etaAt = etaAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case trackingNumber = "tracking_number"
        case carrier
        case status
        case createdAt = "created_at"
        case trackingUrl = "tracking_url"
        case etaAt = "eta_at"
    }

    var resolvedTrackingURL: URL? {
        if let trackingUrl,
           !trackingUrl.isEmpty,
           let url = URL(string: trackingUrl) {
            return url
        }

        guard !trackingNumber.isEmpty,
              let encodedTracking = trackingNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        return URL(string: "https://t.17track.net/en#nums=\(encodedTracking)")
    }
}

/// A row in `public.review_items` — an email the autopilot couldn't
/// confidently classify (or a shipment it couldn't match to an order).
/// Surfaced at the bottom of the Orders tab for the user to confirm or
/// dismiss; resolution feeds the `learned_senders` table so future
/// emails from the same sender skip the queue.
struct ReviewItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let userId: UUID
    let type: String
    let reason: String
    let suggestedAction: String?
    let confidenceScore: Double
    let resolvedAt: Date?
    let createdAt: Date

    // Source-of-truth fields populated by orders-autopilot.ts when the
    // review item is created. Older rows (pre-migration 20260426) have
    // these as nil — UI falls back to the `reason` text in that case.
    let sourceEmailId: String?
    let sourceSubject: String?
    let sourceSenderEmail: String?
    let sourceSenderName: String?
    let suggestedMerchant: String?
    let suggestedOrderNumber: String?
    let suggestedTotalAmount: Decimal?
    let suggestedCurrency: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case reason
        case suggestedAction = "suggested_action"
        case confidenceScore = "confidence_score"
        case resolvedAt = "resolved_at"
        case createdAt = "created_at"
        case sourceEmailId = "source_email_id"
        case sourceSubject = "source_subject"
        case sourceSenderEmail = "source_sender_email"
        case sourceSenderName = "source_sender_name"
        case suggestedMerchant = "suggested_merchant"
        case suggestedOrderNumber = "suggested_order_number"
        case suggestedTotalAmount = "suggested_total_amount"
        case suggestedCurrency = "suggested_currency"
    }

    /// Best-effort merchant label for list rendering. Prefers the
    /// autopilot's structured guess; falls back to the From: display
    /// name; falls back to the bare sender domain stem; "Unknown" only
    /// when we have nothing.
    var displayMerchant: String {
        if let m = suggestedMerchant?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { return m }
        if let n = sourceSenderName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        if let s = sourceSenderEmail, let at = s.firstIndex(of: "@") {
            let host = String(s[s.index(after: at)...])
            let stem = host.split(separator: ".").first.map(String.init) ?? host
            return stem.prefix(1).uppercased() + stem.dropFirst()
        }
        return "Unknown sender"
    }

    var displaySubject: String {
        sourceSubject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? reason
    }
}

/// One line on an order — what was actually purchased.
/// Backed by `public.order_items`, populated by GPT-4o-mini extraction
/// in the orders-autopilot pipeline.
struct OrderItem: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: UUID
    let orderId: UUID
    let name: String
    let quantity: Decimal
    let unitPrice: Decimal?
    let currency: String?
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case name
        case quantity
        case unitPrice = "unit_price"
        case currency
        case position
    }

    /// Pretty quantity — drops the `.0` on integer counts. "1" not "1.0".
    var displayQuantity: String {
        let n = NSDecimalNumber(decimal: quantity)
        if n.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(n.intValue)
        }
        return n.stringValue
    }

    /// Formatted unit price respecting the currency. Empty when nil.
    var displayUnitPrice: String {
        guard let unitPrice else { return "" }
        return PerchFormatters.currency(code: currency ?? "USD")
            .string(from: NSDecimalNumber(decimal: unitPrice)) ?? ""
    }
}

struct OrderWithShipments: Identifiable, Sendable, Equatable {
    let order: Order
    let shipments: [Shipment]
    let items: [OrderItem]

    var id: UUID { order.id }

    init(order: Order, shipments: [Shipment], items: [OrderItem] = []) {
        self.order = order
        self.shipments = shipments
        self.items = items
    }

    var primaryShipment: Shipment? {
        shipments.sorted { $0.createdAt > $1.createdAt }.first
    }

    var displayStatus: String {
        primaryShipment?.status ?? order.status
    }

    var displayDate: Date {
        order.manualDeliveredAt ?? primaryShipment?.createdAt ?? order.createdAt
    }

    /// Status that respects manual delivery overrides.
    /// If the user has manually marked the order delivered, this always returns "delivered"
    /// regardless of what automated tracking or the `status` column say.
    var effectiveStatus: String {
        if order.isManuallyDelivered { return "delivered" }
        return primaryShipment?.status ?? order.status
    }

    /// Phase 1 ETA (2026-04-27): the earliest non-delivered ETA across
    /// this order's shipments. Returns nil when no shipment has an
    /// ETA, or when all shipments are delivered (delivered status pill
    /// takes over). Per the design, mental model is "next thing
    /// arriving" — multi-shipment orders show their soonest expected
    /// delivery, not the latest.
    var effectiveETA: Date? {
        if order.isManuallyDelivered { return nil }
        return shipments
            .filter { $0.status.lowercased() != "delivered" }
            .compactMap { $0.etaAt }
            .min()
    }

    /// Projects the canonical orders + shipments model into the lightweight delivery payload
    /// shape still used by some app surfaces (home/search/live activity).
    /// This is an in-memory adapter only — the source of truth remains the orders tables.
    var trackedDeliveryData: DeliveryData {
        let shipment = primaryShipment
        let trackingNumber = shipment?.trackingNumber ?? order.orderNumber
        let carrier = shipment?.carrier ?? order.merchant
        let trackingUrl = shipment?.resolvedTrackingURL?.absoluteString
        let description = order.orderNumber.isEmpty ? nil : "Order \(order.orderNumber)"

        return DeliveryData(
            orderId: order.id.uuidString,
            carrier: carrier,
            trackingNumber: trackingNumber,
            status: effectiveStatus,
            eta: nil,
            items: [
                DeliveryItem(
                    name: order.merchant,
                    quantity: 1,
                    description: description
                )
            ],
            trackingUrl: trackingUrl
        )
    }
}
