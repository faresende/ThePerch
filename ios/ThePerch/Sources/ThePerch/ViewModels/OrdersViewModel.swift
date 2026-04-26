import Foundation
import Observation

@Observable
@MainActor
final class OrdersViewModel {
    var orders: [OrderWithShipments] = []
    var reviewItems: [ReviewItem] = []
    var isLoading = false
    var error: String?

    /// Set of review-item ids currently being resolved (so the row can
    /// show a spinner / disable buttons during the network roundtrip).
    var resolvingReviewIds: Set<UUID> = []

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
            // Fetch orders + review queue in parallel — the review
            // section shows up at the bottom of the same screen, so
            // there's no point blocking one on the other.
            async let ordersTask = ordersService.fetchOrders(forceRefresh: forceRefresh)
            async let reviewTask = ordersService.fetchUnresolvedReviewItems()
            orders = try await ordersTask
            // Review-queue fetch failures shouldn't kill the orders
            // load — fall back to "no review items" silently.
            do {
                reviewItems = try await reviewTask
            } catch {
#if DEBUG
                print("[OrdersViewModel] fetchUnresolvedReviewItems failed: \(error)")
#endif
                reviewItems = []
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Review queue actions

    /// User tapped "Add as order" on a review-queue row. Creates the
    /// order, writes the (sender → merchant) learned mapping, and
    /// removes the row from the queue.
    func confirmReviewItem(_ item: ReviewItem) async {
        resolvingReviewIds.insert(item.id)
        defer { resolvingReviewIds.remove(item.id) }
        do {
            _ = try await ordersService.confirmReviewItemAsOrder(item)
            // Reload everything — the new order should appear in Active
            // and the review item should drop off the queue.
            await loadOrders(forceRefresh: true)
        } catch {
            self.error = "Couldn't add as order: \(error.localizedDescription)"
        }
    }

    /// User tapped "Not an order" on a review-queue row. Just marks
    /// the row resolved — no learned-senders write (deferred per spec).
    func dismissReviewItem(_ item: ReviewItem) async {
        resolvingReviewIds.insert(item.id)
        defer { resolvingReviewIds.remove(item.id) }
        do {
            try await ordersService.dismissReviewItem(item)
            // Optimistic local removal — avoids a full reload just to
            // drop one row.
            reviewItems.removeAll { $0.id == item.id }
        } catch {
            self.error = "Couldn't dismiss: \(error.localizedDescription)"
        }
    }

    // MARK: - Manual Delivery Override

    /// Marks an order as delivered by the user. Persists to Supabase and reloads.
    /// The `manual_delivered_at` DB column is never written by automated agents,
    /// so this override cannot be silently clobbered by later tracking updates.
    func markAsDelivered(_ order: OrderWithShipments) async {
        do {
            try await ordersService.markAsDelivered(orderId: order.id)
            // Reload to reflect the persisted state from the server
            await loadOrders(forceRefresh: true)
        } catch {
            self.error = "Couldn't mark as delivered: \(error.localizedDescription)"
        }
    }

    /// Reverses a manual delivery override, handing control back to automated tracking.
    func undoDelivered(_ order: OrderWithShipments) async {
        do {
            try await ordersService.undoDelivered(orderId: order.id)
            await loadOrders(forceRefresh: true)
        } catch {
            self.error = "Couldn't undo delivery override: \(error.localizedDescription)"
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
        // Manual override always wins — the user explicitly set this and automated
        // agents cannot overwrite manual_delivered_at, so it stays sticky.
        if order.order.isManuallyDelivered { return "delivered" }

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
