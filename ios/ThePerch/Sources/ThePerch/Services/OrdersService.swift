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
        let iso = PerchFormatters.iso8601.string(from: .now)
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

    /// Confirm a review item as a real order. Behaviour depends on type:
    ///
    /// - **`orphan_shipment` / `shipment_no_order`**: the email is a
    ///   shipping notification we couldn't match to any existing order
    ///   at autopilot time. Confirming here means "yes, this belongs to
    ///   the merchant we guessed" — but odds are an order row already
    ///   exists for that merchant (the missing tracking number on the
    ///   email is what broke matching, not the merchant). We try to
    ///   merge: find an open order for the same normalized merchant,
    ///   append this email's id to its `source_email_ids`, and reuse it.
    ///   Falls back to creating a new order only when no merge target
    ///   exists.
    ///
    /// - **All other types** (`other`, etc.): user is explicitly saying
    ///   "this is a new order I want tracked" — insert a fresh row.
    ///
    /// Either way: writes the (sender → merchant) learned mapping and
    /// resolves the review item. Returns the order id (existing or new).
    @discardableResult
    func confirmReviewItemAsOrder(_ item: ReviewItem) async throws -> UUID {
        let merchant = item.displayMerchant
        let normalized = merchant
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        // 1. For shipping-style review items, prefer merging into an
        //    existing open order for the same merchant.
        let isShippingType = item.type == "orphan_shipment"
                          || item.type == "shipment_no_order"
        if isShippingType, let existingId = try await mergeShippingEmailIntoOpenOrder(
            userId: item.userId,
            normalizedMerchant: normalized,
            sourceEmailId: item.sourceEmailId
        ) {
            // Sender→merchant learning + review-item resolution still
            // happen below by falling through to the same code that
            // runs after the insert — so we land in step 2/3 with
            // `orderId = existingId` instead of a fresh row.
            try await runPostConfirmHousekeeping(
                item: item,
                merchant: merchant,
                orderId: existingId
            )
            return existingId
        }

        // 2. No merge target — create a new order. We mirror the
        //    autopilot's order shape so rows from the review queue
        //    feel identical to autopilot ones.
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

        try await runPostConfirmHousekeeping(
            item: item,
            merchant: merchant,
            orderId: orderId
        )
        return orderId
    }

    /// Look for an open (status != 'delivered', resolved at the order
    /// level) order for the same merchant, and append this shipping
    /// email's id to its `source_email_ids`. Returns the matched
    /// order's id if a merge happened, nil if no candidate was found.
    ///
    /// Match key: normalized merchant only. We don't match on
    /// order_number because shipment-style review items by definition
    /// arrived without an order_number to compare against.
    private func mergeShippingEmailIntoOpenOrder(
        userId: UUID,
        normalizedMerchant: String,
        sourceEmailId: String?
    ) async throws -> UUID? {
        // Newest-first so the email lands on the most recent purchase
        // when the merchant has multiple in flight.
        struct OrderRow: Decodable {
            let id: UUID
            let source_email_ids: [String]?
        }
        let result = try await supabaseService.databaseClient
            .from("orders")
            .select("id, source_email_ids")
            .eq("user_id", value: userId.uuidString)
            .eq("normalized_merchant", value: normalizedMerchant)
            .neq("status", value: "delivered")
            .is("manual_delivered_at", value: nil)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()

        let decoded: [OrderRow]
        do {
            decoded = try JSONDecoder().decode([OrderRow].self, from: result.data)
        } catch {
#if DEBUG
            print("[OrdersService] mergeShippingEmail: decode failed: \(error)")
#endif
            return nil
        }
        guard let target = decoded.first else { return nil }

        // Append the email id to source_email_ids if not already there.
        var ids = target.source_email_ids ?? []
        if let eid = sourceEmailId, !ids.contains(eid) {
            ids.append(eid)
        }
        struct MergePayload: Encodable {
            let source_email_ids: [String]
            let updated_at: String
        }
        let now = PerchFormatters.iso8601.string(from: .now)
        try await supabaseService.databaseClient
            .from("orders")
            .update(MergePayload(source_email_ids: ids, updated_at: now))
            .eq("id", value: target.id.uuidString)
            .execute()
        return target.id
    }

    /// Shared post-confirm work: write the sender→merchant learned
    /// mapping (when we have a sender) and resolve the review item.
    /// Pulled out so both the create-new and merge-into-existing
    /// paths produce identical side-effects.
    private func runPostConfirmHousekeeping(
        item: ReviewItem,
        merchant: String,
        orderId: UUID
    ) async throws {
        if let senderEmail = item.sourceSenderEmail?.lowercased(), !senderEmail.isEmpty {
            try? await upsertLearnedSender(
                userId: item.userId,
                senderEmail: senderEmail,
                merchantName: merchant,
                learnedFromEmailId: item.sourceEmailId,
                learnedFromReviewItemId: item.id
            )
        }
        try await resolveReviewItem(item.id)
        _ = orderId  // reserved for future "linked order id" telemetry
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
        let now = PerchFormatters.iso8601.string(from: .now)
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
        let now = PerchFormatters.iso8601.string(from: .now)
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

    // MARK: - Corrections (Phase 1)
    //
    // The corrections-and-rules feedback loop. Each method calls a
    // SECURITY DEFINER Postgres RPC that does the insert + state
    // transition atomically. The RPC pattern (vs raw .from() writes)
    // gives us:
    //   1. Atomicity — insert + status flip in one round-trip.
    //   2. Server-side parse_trace snapshot — iOS doesn't need to
    //      know the trace's shape to capture it for rule-distillation.
    //   3. Symmetric undo — `cancel_order_correction` reverses the
    //      whole transaction.
    //
    // RPCs defined in supabase/migrations/20260427000000_order_corrections.sql.

    /// Record a correction against an order. Returns a receipt the
    /// caller can hold onto for the undo affordance (only relevant
    /// for `.notAnOrder` — the other kinds don't show an undo toast).
    func recordCorrection(orderId: UUID, kind: CorrectionKind) async throws -> CorrectionReceipt {
        do {
            let response = try await supabaseService.databaseClient
                .rpc("record_order_correction",
                     params: RecordCorrectionArgs(p_order_id: orderId, p_kind: kind.rawValue))
                .execute()
            // RPC returns a uuid (the correction row's id)
            let correctionId = try orderDecoder.decode(UUID.self, from: response.data)
            return CorrectionReceipt(id: correctionId, kind: kind, orderId: orderId)
        } catch {
            throw OrdersServiceError.updateFailed(error.localizedDescription)
        }
    }

    /// Reverse a correction — used by the undo toast. Symmetric to
    /// `recordCorrection`: deletes the correction row and reverses
    /// the state transition. `wrongTracking` corrections leave the
    /// nulled tracking nulled (re-scanning the carrier email is the
    /// only honest way to restore it).
    func cancelCorrection(_ correctionId: UUID) async throws {
        do {
            try await supabaseService.databaseClient
                .rpc("cancel_order_correction",
                     params: CancelCorrectionArgs(p_correction_id: correctionId))
                .execute()
        } catch {
            throw OrdersServiceError.updateFailed(error.localizedDescription)
        }
    }

    /// Fetch the `parse_trace` JSONB column for a single order. Used
    /// by the long-press "Why this is an order?" debug peek. Returned
    /// as a `[String: Any]` dictionary parsed via JSONSerialization so
    /// the renderer is resilient to scanner version drift — when new
    /// fields land, the sheet just shows them without iOS needing a
    /// release.
    ///
    /// Returns `nil` for legacy rows (created before parse-trace
    /// landed) and on any decode/network error (caller renders the
    /// "no parse trace" empty state).
    func fetchParseTrace(orderId: UUID) async throws -> [String: Any]? {
        // We intentionally avoid generating a Swift type for the trace —
        // the shape evolves on the scanner side (versioned via the
        // `version` field) and we'd rather render whatever ships
        // than fail to compile.
        do {
            let result = try await supabaseService.databaseClient
                .from("orders")
                .select("parse_trace")
                .eq("id", value: orderId.uuidString)
                .single()
                .execute()

            // Result data is a JSON object: { "parse_trace": {...} | null }
            guard
                let outer = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
                let trace = outer["parse_trace"] as? [String: Any]
            else {
                return nil
            }
            return trace
        } catch {
            throw OrdersServiceError.updateFailed(error.localizedDescription)
        }
    }
}

// MARK: - RPC arg structs
//
// Marked `nonisolated` because this project sets
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — without an explicit
// opt-out the synthesized Encodable conformance would be main-actor-
// isolated, which fails the Sendable parameter on .rpc(...).
nonisolated private struct RecordCorrectionArgs: Encodable, Sendable {
    let p_order_id: UUID
    let p_kind: String
}

nonisolated private struct CancelCorrectionArgs: Encodable, Sendable {
    let p_correction_id: UUID
}

// MARK: - Correction Types

enum CorrectionKind: String, Codable, Sendable {
    case notAnOrder       = "not_an_order"
    case wrongTracking    = "wrong_tracking"
    case alreadyDelivered = "already_delivered"

    /// Human-readable label for the swipe-action button.
    var actionLabel: String {
        switch self {
        case .notAnOrder:       return "Not an order"
        case .wrongTracking:    return "Wrong tracking"
        case .alreadyDelivered: return "Already delivered"
        }
    }

    /// SF Symbol for the swipe-action button.
    var actionSymbol: String {
        switch self {
        case .notAnOrder:       return "xmark.bin"
        case .wrongTracking:    return "shippingbox.and.arrow.backward"
        case .alreadyDelivered: return "checkmark.circle"
        }
    }

    /// Whether this kind shows an undo toast after firing.
    /// Only `.notAnOrder` gets the toast — the other two are recoverable
    /// through other paths (re-scan for tracking; repeat-swipe for delivered).
    var showsUndoToast: Bool {
        self == .notAnOrder
    }
}

/// Returned by `recordCorrection`. The undo toast holds onto this
/// for the 5s undo window — tapping "Undo" calls `cancelCorrection(receipt.id)`.
struct CorrectionReceipt: Identifiable, Sendable, Equatable {
    let id: UUID            // correction row id (used for cancellation)
    let kind: CorrectionKind
    let orderId: UUID
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
