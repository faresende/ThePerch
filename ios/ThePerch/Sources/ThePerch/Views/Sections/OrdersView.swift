import SwiftUI

struct OrdersView: View {
    @Environment(\.perchPalette) private var palette

    @State private var viewModel = OrdersViewModel()
    @State private var cardsAppeared = false
    /// ID of the order whose card is currently expanded (showing items
    /// + order #). Only one expanded at a time; tapping a different
    /// card collapses the previous one. Mirrors WorkoutView's
    /// expandedSessionId pattern.
    @State private var expandedOrderId: UUID?

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

    /// Toggle the expanded card. Tapping the already-expanded card
    /// collapses it; tapping a different card moves the expansion
    /// (only one card is expanded at any time). Spring animation
    /// matches the workout-card pattern (response: 0.3, damping: 0.7).
    private func toggleExpanded(_ order: OrderWithShipments) {
        PerchMotion.withOptionalAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if expandedOrderId == order.id {
                expandedOrderId = nil
            } else {
                expandedOrderId = order.id
            }
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
                    tint: palette.kinetic,
                    orders: viewModel.activeOrders,
                    cardsAppeared: cardsAppeared,
                    expandedOrderId: expandedOrderId,
                    onToggleExpanded: toggleExpanded,
                    onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                    onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                )

                if !viewModel.issueOrders.isEmpty {
                    OrdersGroupSection(
                        title: "Issues",
                        subtitle: "Exceptions and orders that need a closer look.",
                        icon: "exclamationmark.triangle.fill",
                        tint: palette.error,
                        orders: viewModel.issueOrders,
                        cardsAppeared: cardsAppeared,
                        startIndex: viewModel.activeOrders.count,
                        expandedOrderId: expandedOrderId,
                        onToggleExpanded: toggleExpanded,
                        onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                        onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                    )
                }

                DeliveredOrdersSection(
                    orders: viewModel.deliveredOrders,
                    cardsAppeared: cardsAppeared,
                    startIndex: viewModel.activeOrders.count + viewModel.issueOrders.count,
                    expandedOrderId: expandedOrderId,
                    onToggleExpanded: toggleExpanded,
                    onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                    onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                )

                // Bottom-of-tab review queue — emails the autopilot
                // couldn't classify with confidence (Tier 2 LLM said
                // "not purchase" or was uncertain). Hidden when empty.
                // Each row has inline Confirm / Dismiss buttons that
                // teach the system via `learned_senders`.
                if !viewModel.reviewItems.isEmpty {
                    ReviewQueueSection(
                        items: viewModel.reviewItems,
                        resolvingIds: viewModel.resolvingReviewIds,
                        onConfirm: { item in Task { await viewModel.confirmReviewItem(item) } },
                        onDismiss: { item in Task { await viewModel.dismissReviewItem(item) } }
                    )
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        }
    }
}

// MARK: - Review Queue Section

/// Section at the bottom of the Orders tab listing emails the autopilot
/// couldn't classify with confidence. Each row shows the email subject,
/// sender, and inline Confirm / Dismiss buttons. Resolution writes to
/// `learned_senders` so future emails from the same sender skip the
/// queue (see autopilot Tier-3 design doc).
struct ReviewQueueSection: View {
    @Environment(\.perchPalette) private var palette

    let items: [ReviewItem]
    let resolvingIds: Set<UUID>
    let onConfirm: (ReviewItem) -> Void
    let onDismiss: (ReviewItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            OrdersSectionHeader(
                title: "Needs review",
                subtitle: "Ambiguous emails the autopilot couldn't confidently classify. Confirm or dismiss to teach the system.",
                icon: "questionmark.circle.fill",
                tint: palette.kinetic,
                count: items.count
            )

            VStack(spacing: PerchTheme.Spacing.small) {
                ForEach(items) { item in
                    ReviewQueueRow(
                        item: item,
                        isResolving: resolvingIds.contains(item.id),
                        onConfirm: { onConfirm(item) },
                        onDismiss: { onDismiss(item) }
                    )
                }
            }
        }
    }
}

private struct ReviewQueueRow: View {
    @Environment(\.perchPalette) private var palette

    let item: ReviewItem
    let isResolving: Bool
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
            // Top: merchant guess (kicker-style) on the left, freshness
            // on the right.
            HStack(alignment: .firstTextBaseline) {
                Text(item.displayMerchant)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundColor(palette.muted)
                    .lineLimit(1)
                Spacer(minLength: PerchTheme.Spacing.small)
                Text(relativeTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.faint)
            }

            // Middle: subject (the most useful preview a user can scan).
            Text(item.displaySubject)
                .font(.system(size: 15, weight: .regular, design: .serif).italic())
                .foregroundColor(palette.ink)
                .lineLimit(2)

            // Sender email small + muted, only when available.
            if let s = item.sourceSenderEmail, !s.isEmpty {
                Text(s)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Bottom: action row. Spinner replaces both buttons while
            // a resolution is in flight.
            HStack(spacing: PerchTheme.Spacing.small) {
                Spacer()
                if isResolving {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(palette.kinetic)
                } else {
                    Button(action: onDismiss) {
                        Text("Not an order")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(palette.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(palette.line.opacity(0.55))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss \(item.displayMerchant)")

                    Button(action: onConfirm) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Add as order")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(palette.kinetic)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(item.displayMerchant) as order")
                }
            }
            .padding(.top, PerchTheme.Spacing.xxxSmall)
        }
        .padding(PerchTheme.Card.padding)
        .background(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .stroke(palette.line.opacity(0.6), lineWidth: 1)
        )
    }

    private var relativeTime: String {
        let interval = Date.now.timeIntervalSince(item.createdAt)
        let minutes = Int(interval / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

struct OrdersGroupSection: View {
    @Environment(\.perchPalette) private var palette

    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let orders: [OrderWithShipments]
    let cardsAppeared: Bool
    var startIndex: Int = 0
    /// ID of the currently-expanded card (parent-owned, OrdersView).
    /// nil when no card is expanded.
    var expandedOrderId: UUID? = nil
    /// Toggle handler — fires on tap of a card.
    var onToggleExpanded: ((OrderWithShipments) -> Void)? = nil
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
                    .foregroundColor(palette.faint)
                    .padding(.top, PerchTheme.Spacing.xxxSmall)
            } else {
                VStack(spacing: PerchTheme.Spacing.medium) {
                    ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                        Button {
                            PerchHaptics.light()
                            onToggleExpanded?(order)
                        } label: {
                            OrderCard(
                                model: order,
                                isExpanded: expandedOrderId == order.id,
                                onMarkDelivered: onMarkDelivered.map { cb in { cb(order) } },
                                onUndoDelivered: onUndoDelivered.map { cb in { cb(order) } }
                            )
                            .cardAppear(index: startIndex + index, appeared: cardsAppeared)
                        }
                        .buttonStyle(.plain)
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
    @Environment(\.perchPalette) private var palette

    let orders: [OrderWithShipments]
    let cardsAppeared: Bool
    var startIndex: Int = 0
    /// Per-card item-list expansion (parent-owned). Same UUID-based
    /// state model as OrdersGroupSection.
    var expandedOrderId: UUID? = nil
    var onToggleExpanded: ((OrderWithShipments) -> Void)? = nil
    var onMarkDelivered: ((OrderWithShipments) -> Void)?
    var onUndoDelivered: ((OrderWithShipments) -> Void)?

    /// Section-level toggle: whether the entire delivered list is
    /// shown. Distinct from per-card item-list expansion (above).
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            if orders.isEmpty {
                OrdersSectionHeader(
                    title: "Delivered",
                    subtitle: "Completed orders that have already landed.",
                    icon: "checkmark.circle.fill",
                    tint: palette.wellness,
                    count: 0
                )

                Text("No delivered orders yet.")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(palette.faint)
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
                        tint: palette.wellness,
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
                                        Button {
                                            PerchHaptics.light()
                                            onToggleExpanded?(order)
                                        } label: {
                                            OrderCard(
                                                model: order,
                                                isExpanded: expandedOrderId == order.id,
                                                onMarkDelivered: onMarkDelivered.map { cb in { cb(order) } },
                                                onUndoDelivered: onUndoDelivered.map { cb in { cb(order) } }
                                            )
                                            .cardAppear(index: startIndex + displayIndex(for: order), appeared: cardsAppeared)
                                        }
                                        .buttonStyle(.plain)
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
                .foregroundColor(palette.muted)
                .textCase(.uppercase)

            Spacer(minLength: 0)

            Text("\(group.orders.count)")
                .font(PerchTheme.Font.microNumeric)
                .foregroundColor(palette.faint)
                .padding(.horizontal, PerchTheme.Spacing.small)
                .padding(.vertical, PerchTheme.Spacing.xxxSmall)
                .background(PerchTheme.background.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(palette.line.opacity(0.65), lineWidth: 1)
                )
        }
        .padding(.horizontal, PerchTheme.Spacing.small)
        .padding(.vertical, PerchTheme.Spacing.xxSmall)
        .background(palette.chipBg)
        .cornerRadius(PerchTheme.Card.innerCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                .stroke(palette.line.opacity(0.5), lineWidth: 1)
        )
    }
}

struct OrdersSectionHeader: View {
    @Environment(\.perchPalette) private var palette

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
                        .foregroundColor(palette.ink)

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
                    .foregroundColor(palette.ink.opacity(0.72))
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.muted)
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
