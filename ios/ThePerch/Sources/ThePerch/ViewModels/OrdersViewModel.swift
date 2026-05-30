import Foundation
import Observation

@Observable
@MainActor
final class OrdersViewModel {
    var orders: [OrderWithShipments] = [] {
        didSet { recomputeGroupings() }
    }
    var reviewItems: [ReviewItem] = []
    var isLoading = false
    var error: String?

    /// Set of review-item ids currently being resolved (so the row can
    /// show a spinner / disable buttons during the network roundtrip).
    var resolvingReviewIds: Set<UUID> = []

    // MARK: - Corrections (Phase 1)
    //
    // The currently-active undo receipt — non-nil for the 5s window
    // after a `.notAnOrder` swipe. The toast view binds to this value;
    // setting it to nil dismisses the toast (whether by user-tap-undo,
    // timer expiry, or a follow-up correction overwriting it).
    var activeUndoReceipt: CorrectionReceipt?
    /// Set of order ids currently animating out via a swipe correction.
    /// Used to block double-swipes and to drive `withAnimation` scoping
    /// in the view.
    private(set) var correctingOrderIds: Set<UUID> = []
    private var undoTask: Task<Void, Never>?

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

    /// Warm-path entry: hydrate `orders` directly from a list the
    /// dashboard has already fetched. No network. The OrdersView's
    /// task block calls this when DashboardViewModel.trackedOrders
    /// is non-empty so a fresh navigation to the section renders
    /// instantly. Reviewable-queue items still need a separate
    /// fetch — see `loadReviewItemsOnly`.
    func hydrateFromDashboard(_ trackedOrders: [OrderWithShipments]) {
        orders = trackedOrders
        error = nil
    }

    /// Companion to `hydrateFromDashboard` — fetches just the
    /// unresolved review-queue slice. The dashboard doesn't carry
    /// that data so we still need this round-trip, but it can
    /// load in the background without blocking the orders list.
    func loadReviewItemsOnly() async {
        do {
            reviewItems = try await ordersService.fetchUnresolvedReviewItems()
        } catch {
#if DEBUG
            print("[OrdersViewModel] loadReviewItemsOnly failed: \(error)")
#endif
            // Silent — review queue empty is the same state as "no items".
            reviewItems = []
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

    // MARK: - Corrections (Phase 1)
    //
    // Three swipe actions on each order card. `recordCorrection` calls
    // the server-side RPC, then optimistically removes the row from
    // the local list (so the swipe-to-dismiss animation feels instant).
    // For `.notAnOrder`, we set `activeUndoReceipt` and start a 5s
    // timer; the UndoCorrectionToast binds to that value.

    func recordCorrection(_ order: OrderWithShipments, kind: CorrectionKind) async {
        guard !correctingOrderIds.contains(order.id) else { return }
        correctingOrderIds.insert(order.id)
        defer { correctingOrderIds.remove(order.id) }

        do {
            let receipt = try await ordersService.recordCorrection(
                orderId: order.id,
                kind: kind
            )
            // Optimistic local mutation — avoids a full reload.
            // For all three kinds, the row's display state changes:
            //   .notAnOrder       — drops out of activeOrders (status flipped to dismissed_by_user)
            //   .wrongTracking    — shipment cleared, re-render with "tracking pending"
            //   .alreadyDelivered — moves to delivered group
            // The simplest correct behavior is a full reload.
            await loadOrders(forceRefresh: true)

            if kind.showsUndoToast {
                presentUndo(receipt)
            }
        } catch {
            self.error = "Couldn't save correction: \(error.localizedDescription)"
        }
    }

    /// Cancel the active undo receipt — fired by the toast's "Undo" button.
    /// Idempotent: a second call after the toast has already auto-dismissed
    /// is a silent no-op.
    func cancelActiveUndo() async {
        guard let receipt = activeUndoReceipt else { return }
        activeUndoReceipt = nil
        undoTask?.cancel()
        undoTask = nil
        do {
            try await ordersService.cancelCorrection(receipt.id)
            await loadOrders(forceRefresh: true)
        } catch {
            self.error = "Couldn't undo: \(error.localizedDescription)"
        }
    }

    private func presentUndo(_ receipt: CorrectionReceipt) {
        activeUndoReceipt = receipt
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.activeUndoReceipt?.id == receipt.id else { return }
                self?.activeUndoReceipt = nil
            }
        }
    }

    /// Cached groupings recomputed exactly once per `orders` mutation
    /// (via the `didSet` hook above). Previous version recomputed via a
    /// computed property on every read — and `OrdersView.body` plus
    /// `HubTab.OrdersSectionContent.body` between them read these
    /// 6+ times per render, multiplied by every realtime tick.
    private var _activeOrders: [OrderWithShipments] = []
    private var _deliveredOrders: [OrderWithShipments] = []
    private var _issueOrders: [OrderWithShipments] = []

    var activeOrders: [OrderWithShipments] { _activeOrders }
    var deliveredOrders: [OrderWithShipments] { _deliveredOrders }
    var issueOrders: [OrderWithShipments] { _issueOrders }

    /// Two-zone tracker buckets (In Transit / Expected / Delivered /
    /// Hidden), recomputed alongside the legacy groupings on every
    /// `orders` mutation. The Hub renders `inTransit` + `expected`;
    /// the Past-Orders sheet still leans on the legacy groupings above.
    private var _zones: OrderZones.Zones = .init(inTransit: [], expected: [], delivered: [], hidden: [])
    var zones: OrderZones.Zones { _zones }

    private func recomputeGroupings() {
        var active: [OrderWithShipments] = []
        var delivered: [OrderWithShipments] = []
        var issues: [OrderWithShipments] = []
        active.reserveCapacity(orders.count)

        for order in orders {
            // Phase 1 corrections: dismissed_by_user rows drop out of
            // every visible group. They live on as soft-deleted rows
            // (visible in Past Orders sheet with a "Restore" affordance)
            // but never surface in Today/Active/Delivered/Issues.
            if order.order.isDismissedByUser { continue }

            switch group(for: order) {
            case .active:
                active.append(order)
            case .delivered:
                delivered.append(order)
            case .issues:
                issues.append(order)
            }
        }

        _activeOrders = active
        _deliveredOrders = delivered
        _issueOrders = issues

        // Two-zone tracker: drop dismissed rows up front (partition still
        // routes any stray `hidden==true` rows into its own bucket, which
        // the Hub never renders, so hidden orders can't leak through).
        _zones = OrderZones.partition(orders.filter { !$0.order.isDismissedByUser })
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
