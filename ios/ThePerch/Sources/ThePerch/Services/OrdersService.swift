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
