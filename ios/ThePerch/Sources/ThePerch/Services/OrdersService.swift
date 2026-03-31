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
}
