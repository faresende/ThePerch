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

        async let ordersTask: [Order] = fetchOrdersTable()
        async let shipmentsTask: [Shipment] = fetchShipmentsTable()

        let (orders, shipments) = try await (ordersTask, shipmentsTask)
        let shipmentsByOrderId = Dictionary(grouping: shipments, by: \.orderId)

        let merged = orders.map { order in
            OrderWithShipments(
                order: order,
                shipments: shipmentsByOrderId[order.id, default: []]
                    .sorted { $0.createdAt > $1.createdAt }
            )
        }

        supabaseService.freshnessTracker.recordFetch(for: "deliveries")
        return merged.sorted { lhs, rhs in
            sortDate(for: lhs) > sortDate(for: rhs)
        }
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
