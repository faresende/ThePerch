import SwiftUI

/// Delivery tracking section with active and completed deliveries.
/// Reads records from DashboardViewModel (single-fetch architecture).
struct DeliveriesView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var showCompleted = false
    @State private var cardsAppeared = false

    private let freshnessTracker = DataFreshnessTracker.shared

    private var records: [Record] { dashboardViewModel.deliveryRecords }

    /// Single-pass decode: partition into active vs. completed deliveries.
    private var partitionedDeliveries: (active: [Record], completed: [Record]) {
        var active: [Record] = []
        var completed: [Record] = []
        for record in records {
            guard let delivery = record.asDelivery() else { continue }
            let status = delivery.status.lowercased()
            if status == "delivered" || status == "cancelled" {
                completed.append(record)
            } else {
                active.append(record)
            }
        }
        return (active, completed)
    }

    var activeDeliveries: [Record] { partitionedDeliveries.active }
    var completedDeliveries: [Record] { partitionedDeliveries.completed }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

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
                            retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                            onDismiss: { dashboardViewModel.clearError() }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    if dashboardViewModel.isLoading && records.isEmpty {
                        SkeletonCardsSection(count: 3)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    } else {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Active Deliveries")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            if activeDeliveries.isEmpty {
                                EmptyStateView(
                                    icon: "shippingbox",
                                    title: "No active deliveries",
                                    subtitle: "Tracked packages that are still moving will show up here."
                                )
                            } else {
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
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)

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

                            if completedDeliveries.isEmpty {
                                EmptyStateView(
                                    icon: "checkmark.circle",
                                    title: "No completed deliveries",
                                    subtitle: "Completed deliveries will appear here after they arrive."
                                )
                            } else if showCompleted {
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

}

// MARK: - Preview

#Preview {
    DeliveriesView()
        .environment(DashboardViewModel())
}
