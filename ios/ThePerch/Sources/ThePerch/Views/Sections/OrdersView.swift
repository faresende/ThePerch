import SwiftUI

struct OrdersView: View {
    @State private var viewModel = OrdersViewModel()
    @State private var cardsAppeared = false

    var body: some View {
        @Bindable var vm = viewModel

        ZStack {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    SectionHeader(title: "Orders", freshnessKey: "deliveries")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    if let error = vm.error {
                        ErrorBanner(
                            message: error,
                            retryAction: { Task { await vm.loadOrders(forceRefresh: true) } },
                            onDismiss: { vm.error = nil }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    content

                    Color.clear
                        .frame(height: 0)
                        .onAppear {
                            PerchMotion.withOptionalAnimation { cardsAppeared = true }
                        }

                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await vm.loadOrders(forceRefresh: true)
                PerchHaptics.success()
            }
        }
        .task {
            guard vm.orders.isEmpty else { return }
            await vm.loadOrders()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.orders.isEmpty {
            SkeletonCardsSection(count: 3)
                .padding(.horizontal, PerchTheme.Spacing.large)
        } else if let error = viewModel.error, viewModel.orders.isEmpty {
            EmptyStateView(
                icon: "shippingbox",
                title: "Orders backend unavailable",
                subtitle: error.contains("public.orders")
                    ? "This backend does not have the new orders tables yet, so the Orders tab cannot load real data here yet."
                    : error
            )
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else if viewModel.orders.isEmpty {
            EmptyStateView(
                icon: "shippingbox",
                title: "No orders yet",
                subtitle: "Purchase confirmations and tracked shipments will show up here once Orders Autopilot has something to merge."
            )
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else {
            LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                OrdersGroupSection(
                    title: "Active",
                    subtitle: "Ordered, processing, and in-flight shipments.",
                    orders: viewModel.activeOrders,
                    cardsAppeared: cardsAppeared,
                    onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                    onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                )

                if !viewModel.issueOrders.isEmpty {
                    OrdersGroupSection(
                        title: "Issues",
                        subtitle: "Exceptions and orders that need a closer look.",
                        orders: viewModel.issueOrders,
                        cardsAppeared: cardsAppeared,
                        startIndex: viewModel.activeOrders.count,
                        onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                        onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                    )
                }

                OrdersGroupSection(
                    title: "Delivered",
                    subtitle: "Completed orders that have already landed.",
                    orders: viewModel.deliveredOrders,
                    cardsAppeared: cardsAppeared,
                    startIndex: viewModel.activeOrders.count + viewModel.issueOrders.count,
                    onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                    onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                )
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        }
    }
}

private struct OrdersGroupSection: View {
    let title: String
    let subtitle: String
    let orders: [OrderWithShipments]
    let cardsAppeared: Bool
    var startIndex: Int = 0
    /// Called with the specific order when the user selects "Mark as Delivered".
    var onMarkDelivered: ((OrderWithShipments) -> Void)?
    /// Called with the specific order when the user selects "Undo Delivery Override".
    var onUndoDelivered: ((OrderWithShipments) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxxSmall) {
                Text(title)
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text(subtitle)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
            }

            if orders.isEmpty {
                Text(emptyMessage)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                    .padding(.top, PerchTheme.Spacing.xxxSmall)
            } else {
                VStack(spacing: PerchTheme.Spacing.medium) {
                    ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                        OrderCard(
                            model: order,
                            onMarkDelivered: onMarkDelivered.map { cb in { cb(order) } },
                            onUndoDelivered: onUndoDelivered.map { cb in { cb(order) } }
                        )
                        .cardAppear(index: startIndex + index, appeared: cardsAppeared)
                    }
                }
            }
        }
    }

    private var emptyMessage: String {
        switch title {
        case "Active":
            return "No active orders right now."
        case "Delivered":
            return "No delivered orders yet."
        default:
            return "No orders need attention."
        }
    }
}
