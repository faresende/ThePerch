import Foundation
import Observation

@Observable
@MainActor
final class OrdersViewModel {
    var orders: [OrderWithShipments] = []
    var isLoading = false
    var error: String?

    private let ordersService: OrdersService

    init() {
        self.ordersService = .shared
    }

    init(ordersService: OrdersService) {
        self.ordersService = ordersService
    }

    func loadOrders(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            orders = try await ordersService.fetchOrders(forceRefresh: forceRefresh)
        } catch {
            self.error = error.localizedDescription
        }
    }

    var activeOrders: [OrderWithShipments] {
        groupedOrders.active
    }

    var deliveredOrders: [OrderWithShipments] {
        groupedOrders.delivered
    }

    var issueOrders: [OrderWithShipments] {
        groupedOrders.issues
    }

    private var groupedOrders: (
        active: [OrderWithShipments],
        delivered: [OrderWithShipments],
        issues: [OrderWithShipments]
    ) {
        var active: [OrderWithShipments] = []
        var delivered: [OrderWithShipments] = []
        var issues: [OrderWithShipments] = []

        for order in orders {
            switch group(for: order) {
            case .active:
                active.append(order)
            case .delivered:
                delivered.append(order)
            case .issues:
                issues.append(order)
            }
        }

        return (active, delivered, issues)
    }

    private func group(for order: OrderWithShipments) -> OrderStatusGroup {
        switch normalizedStatus(for: order) {
        case "delivered":
            return .delivered
        case "exception", "needs_review", "issue":
            return .issues
        default:
            return .active
        }
    }

    private func normalizedStatus(for order: OrderWithShipments) -> String {
        let shipmentStatus = order.primaryShipment?.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let orderStatus = order.order.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return shipmentStatus?.isEmpty == false ? shipmentStatus! : orderStatus
    }
}

private enum OrderStatusGroup: Sendable {
    case active
    case delivered
    case issues
}
