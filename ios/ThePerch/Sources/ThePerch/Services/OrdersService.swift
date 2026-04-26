import Foundation
import PostgREST
import Supabase

@MainActor
final class OrdersService {
    static let shared = OrdersService()

    private let supabaseService: SupabaseService
    private let orderDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let shipmentDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        self.supabaseService = .shared
    }

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }

    func fetchOrders(forceRefresh _: Bool = false) async throws -> [OrderWithShipments] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiDebugMockOrders") {
            let merged = debugMockOrders()
            supabaseService.freshnessTracker.recordFetch(for: "deliveries")
            return merged.sorted { lhs, rhs in
                sortDate(for: lhs) > sortDate(for: rhs)
            }
        }
        #endif

        // Fetch orders + shipments + items in parallel. Items extraction
        // (Tier 4) is a per-line product list captured by the GPT-4o-mini
        // pass at autopilot ingest time; on iOS we group by order_id and
        // attach to the matching OrderWithShipments.
        async let ordersTask: [Order] = fetchOrdersTable()
        async let shipmentsTask: [Shipment] = fetchShipmentsTable()
        async let itemsTask: [OrderItem] = fetchOrderItemsTable()

        let (orders, shipments, items) = try await (ordersTask, shipmentsTask, itemsTask)
        let shipmentsByOrderId = Dictionary(grouping: shipments, by: \.orderId)
        let itemsByOrderId = Dictionary(grouping: items, by: \.orderId)

        let merged = orders.map { order in
            OrderWithShipments(
                order: order,
                shipments: shipmentsByOrderId[order.id, default: []]
                    .sorted { $0.createdAt > $1.createdAt },
                items: itemsByOrderId[order.id, default: []]
                    .sorted { $0.position < $1.position }
            )
        }

        supabaseService.freshnessTracker.recordFetch(for: "deliveries")
        return merged.sorted { lhs, rhs in
            sortDate(for: lhs) > sortDate(for: rhs)
        }
    }

    private func fetchOrderItemsTable() async throws -> [OrderItem] {
        let result = try await supabaseService.databaseClient
            .from("order_items")
            .select()
            .order("position", ascending: true)
            .execute()
        let rawArray = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] ?? []
        var items: [OrderItem] = []
        items.reserveCapacity(rawArray.count)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        for item in rawArray {
            do {
                let data = try JSONSerialization.data(withJSONObject: item)
                items.append(try dec.decode(OrderItem.self, from: data))
            } catch {
#if DEBUG
                print("[OrdersService] Dropping malformed order_item: \(error)")
#endif
            }
        }
        return items
    }

    private func fetchOrdersTable() async throws -> [Order] {
        let result = try await supabaseService.databaseClient
            .from("orders")
            .select()
            .order("created_at", ascending: false)
            .execute()

        let rawArray = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] ?? []
        var orders: [Order] = []
        orders.reserveCapacity(rawArray.count)

        for item in rawArray {
            do {
                let data = try JSONSerialization.data(withJSONObject: item)
                orders.append(try orderDecoder.decode(Order.self, from: data))
            } catch {
#if DEBUG
                print("[OrdersService] Dropping malformed order: \(error)")
#endif
            }
        }

        return orders
    }

    private func fetchShipmentsTable() async throws -> [Shipment] {
        let result = try await supabaseService.databaseClient
            .from("shipments")
            .select()
            .order("created_at", ascending: false)
            .execute()

        let rawArray = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] ?? []
        var shipments: [Shipment] = []
        shipments.reserveCapacity(rawArray.count)

        for item in rawArray {
            do {
                let data = try JSONSerialization.data(withJSONObject: item)
                shipments.append(try shipmentDecoder.decode(Shipment.self, from: data))
            } catch {
#if DEBUG
                print("[OrdersService] Dropping malformed shipment: \(error)")
#endif
            }
        }

        return shipments
    }

    private func sortDate(for model: OrderWithShipments) -> Date {
        model.primaryShipment?.createdAt ?? model.order.createdAt
    }

#if DEBUG
    private func debugMockOrders() -> [OrderWithShipments] {
        let now = Date.now

        let penworldId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let bodyFitId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let amazonId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        return [
            OrderWithShipments(
                order: Order(
                    id: penworldId,
                    merchant: "Penworld",
                    orderNumber: "2200082684",
                    total: Decimal(string: "89.00"),
                    currency: "EUR",
                    status: "in_transit",
                    confidence: 0.99,
                    createdAt: now.addingTimeInterval(-86_400 * 5),
                    manualDeliveredAt: nil
                ),
                shipments: [
                    Shipment(
                        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                        orderId: penworldId,
                        trackingNumber: "JVGL06363881001053185034",
                        carrier: "DHL",
                        status: "in_transit",
                        createdAt: now.addingTimeInterval(-86_400),
                        trackingUrl: "https://www.dhl.com/global-en/home/tracking.html?tracking-id=JVGL06363881001053185034"
                    )
                ]
            ),
            OrderWithShipments(
                order: Order(
                    id: bodyFitId,
                    merchant: "Body&Fit",
                    orderNumber: "BF1399824",
                    total: Decimal(string: "114.97"),
                    currency: "EUR",
                    status: "shipped",
                    confidence: 0.98,
                    createdAt: now.addingTimeInterval(-86_400 * 3),
                    manualDeliveredAt: nil
                ),
                shipments: [
                    Shipment(
                        id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
                        orderId: bodyFitId,
                        trackingNumber: "CQ478937250DE",
                        carrier: "DHL",
                        status: "shipped",
                        createdAt: now.addingTimeInterval(-43_200),
                        trackingUrl: "https://www.dhl.com/global-en/home/tracking.html?tracking-id=CQ478937250DE"
                    )
                ]
            ),
            OrderWithShipments(
                order: Order(
                    id: amazonId,
                    merchant: "Amazon",
                    orderNumber: "404-1892456-1182753",
                    total: Decimal(string: "42.99"),
                    currency: "EUR",
                    status: "delivered",
                    confidence: 0.96,
                    createdAt: now.addingTimeInterval(-86_400 * 16),
                    manualDeliveredAt: now.addingTimeInterval(-86_400 * 12)
                ),
                shipments: []
            ),
        ]
    }
#endif

    // MARK: - Manual Delivery Override

    /// Persistently marks an order as delivered by the user.
    /// Sets `manual_delivered_at` to the current timestamp.
    /// Automated agents never touch this column, so it won't be clobbered by tracking updates.
    func markAsDelivered(orderId: UUID) async throws {
        struct DeliveredSet: Encodable {
            // swiftlint:disable:next identifier_name
            let manual_delivered_at: String
        }
        let iso = ISO8601DateFormatter().string(from: .now)
        do {
            try await supabaseService.databaseClient
                .from("orders")
                .update(DeliveredSet(manual_delivered_at: iso))
                .eq("id", value: orderId.uuidString)
                .execute()
        } catch {
            throw OrdersServiceError.updateFailed(error.localizedDescription)
        }
    }

    // MARK: - Review Queue
    //
    // The autopilot creates review_items rows when it can't confidently
    // classify an email (Tier-2 LLM disagreed with Tier-1 keywords, or
    // a shipping email had no matching order). These surface at the
    // bottom of the Orders tab so the user can confirm/reject. Each
    // resolution feeds the `learned_senders` table so future emails
    // from the same sender skip the queue.

    private let reviewItemDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Fetch all unresolved review items for the current user, newest first.
    /// Used by the Orders-tab review queue section.
    func fetchUnresolvedReviewItems() async throws -> [ReviewItem] {
        let result = try await supabaseService.databaseClient
            .from("review_items")
            .select()
            .is("resolved_at", value: nil)
            .order("created_at", ascending: false)
            .execute()

        let rawArray = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] ?? []
        var items: [ReviewItem] = []
        items.reserveCapacity(rawArray.count)
        for item in rawArray {
            do {
                let data = try JSONSerialization.data(withJSONObject: item)
                items.append(try reviewItemDecoder.decode(ReviewItem.self, from: data))
            } catch {
#if DEBUG
                print("[OrdersService] Dropping malformed review_item: \(error)")
#endif
            }
        }
        return items
    }

    /// Confirm a review item as a real order. Creates an `orders` row
    /// from the review item's suggested_* fields, writes the
    /// (sender → merchant) mapping into `learned_senders`, and resolves
    /// the review item. Returns the new order's id.
    @discardableResult
    func confirmReviewItemAsOrder(_ item: ReviewItem) async throws -> UUID {
        let merchant = item.displayMerchant
        let normalized = merchant
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        // 1. Insert the order. We mirror the autopilot's order shape so
        //    rows from the review queue feel identical to autopilot ones.
        struct NewOrder: Encodable {
            let user_id: String
            let merchant_name: String
            let normalized_merchant: String
            let order_number: String?
            let total_amount: Decimal?
            let currency: String
            let source_email_ids: [String]
            let confidence_score: Double
            let status: String
        }
        let body = NewOrder(
            user_id: item.userId.uuidString,
            merchant_name: merchant,
            normalized_merchant: normalized,
            order_number: item.suggestedOrderNumber,
            total_amount: item.suggestedTotalAmount,
            currency: item.suggestedCurrency ?? "USD",
            source_email_ids: item.sourceEmailId.map { [$0] } ?? [],
            confidence_score: 1.0,  // user-confirmed
            status: "ordered"
        )
        let inserted = try await supabaseService.databaseClient
            .from("orders")
            .insert(body)
            .select("id")
            .single()
            .execute()
        let raw = try JSONSerialization.jsonObject(with: inserted.data) as? [String: Any] ?? [:]
        let orderId: UUID = (raw["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()

        // 2. Write the (sender_email → merchant) learned mapping so the
        //    next email from this sender skips the review queue.
        if let senderEmail = item.sourceSenderEmail?.lowercased(), !senderEmail.isEmpty {
            try? await upsertLearnedSender(
                userId: item.userId,
                senderEmail: senderEmail,
                merchantName: merchant,
                learnedFromEmailId: item.sourceEmailId,
                learnedFromReviewItemId: item.id
            )
        }

        // 3. Resolve the review item.
        try await resolveReviewItem(item.id)

        return orderId
    }

    /// Dismiss a review item as not-an-order. v1 just resolves; doesn't
    /// write a `learned_senders` rejection sentinel (deferred per spec —
    /// revisit if the same sender keeps re-queueing).
    func dismissReviewItem(_ item: ReviewItem) async throws {
        try await resolveReviewItem(item.id)
    }

    /// Mark a review_items row resolved. Internal helper.
    private func resolveReviewItem(_ id: UUID) async throws {
        struct ResolvePayload: Encodable {
            let resolved_at: String
            let updated_at: String
        }
        let now = ISO8601DateFormatter().string(from: .now)
        try await supabaseService.databaseClient
            .from("review_items")
            .update(ResolvePayload(resolved_at: now, updated_at: now))
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Upsert a row into `learned_senders`. Internal helper used by
    /// confirmReviewItemAsOrder.
    private func upsertLearnedSender(
        userId: UUID,
        senderEmail: String,
        merchantName: String,
        learnedFromEmailId: String?,
        learnedFromReviewItemId: UUID
    ) async throws {
        let normalized = merchantName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let domain: String? = {
            guard let at = senderEmail.firstIndex(of: "@") else { return nil }
            let host = senderEmail[senderEmail.index(after: at)...]
                .replacingOccurrences(of: "www.", with: "")
            return host.split(separator: ".").dropLast().last.map(String.init)
                ?? host.split(separator: ".").first.map(String.init)
        }()

        struct LearnedSenderUpsert: Encodable {
            let user_id: String
            let sender_email: String
            let sender_domain: String?
            let merchant_name: String
            let normalized_merchant: String
            let learned_from_email_id: String?
            let learned_from_review_item_id: String
            let updated_at: String
        }
        let now = ISO8601DateFormatter().string(from: .now)
        let body = LearnedSenderUpsert(
            user_id: userId.uuidString,
            sender_email: senderEmail,
            sender_domain: domain,
            merchant_name: merchantName,
            normalized_merchant: normalized,
            learned_from_email_id: learnedFromEmailId,
            learned_from_review_item_id: learnedFromReviewItemId.uuidString,
            updated_at: now
        )
        try await supabaseService.databaseClient
            .from("learned_senders")
            .upsert(body, onConflict: "user_id,sender_email")
            .execute()
    }

    /// Reverses a manual delivery override, restoring automated tracking control.
    /// Sets `manual_delivered_at` back to NULL.
    func undoDelivered(orderId: UUID) async throws {
        // Explicit encode(to:) required — Swift's auto-synthesis uses encodeIfPresent
        // which omits nil keys instead of encoding them as JSON null.
        struct DeliveredClear: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeNil(forKey: .manualDeliveredAt)
            }
            private enum CodingKeys: String, CodingKey {
                case manualDeliveredAt = "manual_delivered_at"
            }
        }
        do {
            try await supabaseService.databaseClient
                .from("orders")
                .update(DeliveredClear())
                .eq("id", value: orderId.uuidString)
                .execute()
        } catch {
            throw OrdersServiceError.updateFailed(error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum OrdersServiceError: LocalizedError {
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .updateFailed(let msg): return "Order update failed: \(msg)"
        }
    }
}
