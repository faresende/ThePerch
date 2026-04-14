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
                    icon: "shippingbox.fill",
                    tint: PerchTheme.accent,
                    orders: viewModel.activeOrders,
                    cardsAppeared: cardsAppeared,
                    onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                    onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                )

                if !viewModel.issueOrders.isEmpty {
                    OrdersGroupSection(
                        title: "Issues",
                        subtitle: "Exceptions and orders that need a closer look.",
                        icon: "exclamationmark.triangle.fill",
                        tint: PerchTheme.error,
                        orders: viewModel.issueOrders,
                        cardsAppeared: cardsAppeared,
                        startIndex: viewModel.activeOrders.count,
                        onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                        onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                    )
                }

                DeliveredOrdersSection(
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

struct OrdersGroupSection: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let orders: [OrderWithShipments]
    let cardsAppeared: Bool
    var startIndex: Int = 0
    var onMarkDelivered: ((OrderWithShipments) -> Void)?
    var onUndoDelivered: ((OrderWithShipments) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            OrdersSectionHeader(
                title: title,
                subtitle: subtitle,
                icon: icon,
                tint: tint,
                count: orders.count
            )

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

struct DeliveredOrdersSection: View {
    let orders: [OrderWithShipments]
    let cardsAppeared: Bool
    var startIndex: Int = 0
    var onMarkDelivered: ((OrderWithShipments) -> Void)?
    var onUndoDelivered: ((OrderWithShipments) -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            if orders.isEmpty {
                OrdersSectionHeader(
                    title: "Delivered",
                    subtitle: "Completed orders that have already landed.",
                    icon: "checkmark.circle.fill",
                    tint: PerchTheme.success,
                    count: 0
                )

                Text("No delivered orders yet.")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                    .padding(.top, PerchTheme.Spacing.xxxSmall)
            } else {
                Button {
                    PerchHaptics.light()
                    PerchMotion.withOptionalAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    OrdersSectionHeader(
                        title: "Delivered",
                        subtitle: isExpanded ? "Completed orders that have already landed." : collapsedSummary,
                        icon: "checkmark.circle.fill",
                        tint: PerchTheme.success,
                        count: orders.count,
                        showsDisclosure: true,
                        isExpanded: isExpanded
                    )
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                        ForEach(monthGroups) { group in
                            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                                monthHeader(for: group)

                                VStack(spacing: PerchTheme.Spacing.medium) {
                                    ForEach(group.orders) { order in
                                        OrderCard(
                                            model: order,
                                            onMarkDelivered: onMarkDelivered.map { cb in { cb(order) } },
                                            onUndoDelivered: onUndoDelivered.map { cb in { cb(order) } }
                                        )
                                        .cardAppear(index: startIndex + displayIndex(for: order), appeared: cardsAppeared)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var collapsedSummary: String {
        let monthCount = monthGroups.count
        let monthLabel = monthCount == 1 ? "month" : "months"
        return "\(orders.count) completed orders across \(monthCount) \(monthLabel)."
    }

    private var monthGroups: [DeliveredMonthGroup] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: orders) { order in
            calendar.date(from: calendar.dateComponents([.year, .month], from: order.displayDate)) ?? order.displayDate
        }

        return grouped
            .map { monthStart, monthOrders in
                DeliveredMonthGroup(
                    monthStart: monthStart,
                    orders: monthOrders.sorted { $0.displayDate > $1.displayDate }
                )
            }
            .sorted { $0.monthStart > $1.monthStart }
    }

    private func displayIndex(for order: OrderWithShipments) -> Int {
        orders.firstIndex(where: { $0.id == order.id }) ?? 0
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func monthHeader(for group: DeliveredMonthGroup) -> some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            Text(monthTitle(for: group.monthStart))
                .font(PerchTheme.Font.cardEyebrow)
                .foregroundColor(PerchTheme.textSecondary)
                .textCase(.uppercase)

            Spacer(minLength: 0)

            Text("\(group.orders.count)")
                .font(PerchTheme.Font.microNumeric)
                .foregroundColor(PerchTheme.textTertiary)
                .padding(.horizontal, PerchTheme.Spacing.small)
                .padding(.vertical, PerchTheme.Spacing.xxxSmall)
                .background(PerchTheme.background.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(PerchTheme.border.opacity(0.65), lineWidth: 1)
                )
        }
        .padding(.horizontal, PerchTheme.Spacing.small)
        .padding(.vertical, PerchTheme.Spacing.xxSmall)
        .background(PerchTheme.cardInnerBackground)
        .cornerRadius(PerchTheme.Card.innerCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                .stroke(PerchTheme.border.opacity(0.5), lineWidth: 1)
        )
    }
}

struct OrdersSectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let count: Int
    var showsDisclosure = false
    var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                )

            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxxSmall) {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Text(title)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)

                    Text("\(count)")
                        .font(PerchTheme.Font.microNumeric)
                        .foregroundColor(tint)
                        .padding(.horizontal, PerchTheme.Spacing.small)
                        .padding(.vertical, PerchTheme.Spacing.xxxSmall)
                        .background(tint.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(subtitle)
                    .font(PerchTheme.Font.caption)
                    .fontWeight(.medium)
                    .foregroundColor(PerchTheme.textPrimary.opacity(0.72))
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PerchTheme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .padding(.top, PerchTheme.Spacing.xxxSmall)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct DeliveredMonthGroup: Identifiable {
    let monthStart: Date
    let orders: [OrderWithShipments]

    var id: Date { monthStart }
}
