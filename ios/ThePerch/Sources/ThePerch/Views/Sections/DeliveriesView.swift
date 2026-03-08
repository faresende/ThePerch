import SwiftUI

/// Delivery tracking section with active and completed deliveries.
/// Reads records from DashboardViewModel (single-fetch architecture).
struct DeliveriesView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var showCompleted = false
    @State private var cardsAppeared = false

    private let freshnessTracker = DataFreshnessTracker.shared

    private var records: [Record] { dashboardViewModel.deliveryRecords }

    var activeDeliveries: [Record] {
        records.filter { record in
            if let delivery = record.asDelivery() {
                let status = delivery.status.lowercased()
                return status != "delivered" && status != "cancelled"
            }
            return false
        }
    }

    var completedDeliveries: [Record] {
        records.filter { record in
            if let delivery = record.asDelivery() {
                let status = delivery.status.lowercased()
                return status == "delivered" || status == "cancelled"
            }
            return false
        }
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            if dashboardViewModel.isLoading && records.isEmpty {
                SkeletonDeliveriesSection()
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, 60)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Section header with freshness
                    SectionHeader(title: "Deliveries", freshnessKey: "deliveries")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    // Error banner
                    if dashboardViewModel.error != nil {
                        ErrorBanner(
                            message: "Failed to load deliveries",
                            retryAction: { Task { await dashboardViewModel.refreshRecords() } },
                            onDismiss: { dashboardViewModel.clearError() }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // Active deliveries
                    if !activeDeliveries.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Active Deliveries")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            VStack(spacing: PerchTheme.Spacing.medium) {
                                ForEach(Array(activeDeliveries.enumerated()), id: \.element.id) { index, record in
                                    if let delivery = record.asDelivery() {
                                        DeliveryCard(delivery: delivery)
                                            .cardAppear(index: index, appeared: cardsAppeared)
                                            .contextMenu {
                                                Button {
                                                    Task { await dashboardViewModel.toggleRecordPin(recordId: record.id) }
                                                } label: {
                                                    Label(
                                                        record.pinned ? "Unpin" : "Pin",
                                                        systemImage: record.pinned ? "pin.slash" : "pin"
                                                    )
                                                }
                                            }
                                    }
                                }
                            }
                            .onAppear {
                                PerchMotion.withOptionalAnimation { cardsAppeared = true }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // Completed deliveries (collapsible)
                    if !completedDeliveries.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Button(action: {
                                PerchHaptics.light()
                                showCompleted.toggle()
                            }) {
                                HStack {
                                    Text("Completed Deliveries")
                                        .font(PerchTheme.Font.heading)
                                        .foregroundColor(PerchTheme.textPrimary)

                                    Spacer()

                                    Image(systemName: "chevron.down")
                                        .rotationEffect(.degrees(showCompleted ? 180 : 0))
                                        .foregroundColor(PerchTheme.textSecondary)
                                        .animation(
                                            PerchMotion.prefersReduced ? .none : .easeInOut(duration: 0.2),
                                            value: showCompleted
                                        )
                                }
                            }

                            if showCompleted {
                                VStack(spacing: PerchTheme.Spacing.medium) {
                                    ForEach(completedDeliveries) { record in
                                        if let delivery = record.asDelivery() {
                                            DeliveryCard(delivery: delivery)
                                                .contextMenu {
                                                    Button {
                                                        Task { await dashboardViewModel.toggleRecordPin(recordId: record.id) }
                                                    } label: {
                                                        Label(
                                                            record.pinned ? "Unpin" : "Pin",
                                                            systemImage: record.pinned ? "pin.slash" : "pin"
                                                        )
                                                    }
                                                }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    if activeDeliveries.isEmpty && completedDeliveries.isEmpty {
                        emptyStateView
                    }

                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.refreshRecords()
                await syncLiveActivities()
                PerchHaptics.success()
            }
        }
    }

    /// Syncs Live Activities with current active deliveries.
    private func syncLiveActivities() async {
        let deliveries = activeDeliveries.compactMap { $0.asDelivery() }
        await DeliveryLiveActivityManager.shared.sync(activeDeliveries: deliveries)
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "shippingbox")
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text("No deliveries")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text("Your deliveries will appear here")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PerchTheme.Spacing.large)
    }
}

// MARK: - Preview

#Preview {
    DeliveriesView()
        .environment(DashboardViewModel())
}
