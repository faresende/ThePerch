import SwiftUI

/// Delivery tracking section with active and completed deliveries.
/// Uses the new DeliveryCard with horizontal step progress indicator.
/// Supports swipe actions for pinning items.
struct DeliveriesView: View {
    @State private var viewModel = SectionViewModel(category: .deliveries)
    @State private var showCompleted = false
    @State private var cardsAppeared = false

    private let freshnessTracker = DataFreshnessTracker.shared

    var activeDeliveries: [Record] {
        viewModel.records.filter { record in
            if let delivery = record.asDelivery() {
                let status = delivery.status.lowercased()
                return status != "delivered" && status != "cancelled"
            }
            return false
        }
    }

    var completedDeliveries: [Record] {
        viewModel.records.filter { record in
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

            if viewModel.isLoading && viewModel.records.isEmpty {
                SkeletonDeliveriesSection()
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, 60)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Section header with freshness
                    SectionHeader(title: "Deliveries", freshnessKey: "deliveries")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    // Active deliveries
                    if !activeDeliveries.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Active Deliveries")
                                .font(PerchTheme.Font.headline)
                                .foregroundColor(PerchTheme.textPrimary)

                            VStack(spacing: PerchTheme.Spacing.medium) {
                                ForEach(Array(activeDeliveries.enumerated()), id: \.element.id) { index, record in
                                    if let delivery = record.asDelivery() {
                                        DeliveryCard(delivery: delivery)
                                            .cardAppear(index: index, appeared: cardsAppeared)
                                            .contextMenu {
                                                Button {
                                                    Task { await viewModel.togglePin(recordId: record.id) }
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
                                withAnimation { cardsAppeared = true }
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
                                        .font(PerchTheme.Font.headline)
                                        .foregroundColor(PerchTheme.textPrimary)

                                    Spacer()

                                    Image(systemName: "chevron.down")
                                        .rotationEffect(.degrees(showCompleted ? 180 : 0))
                                        .foregroundColor(PerchTheme.textSecondary)
                                        .animation(.easeInOut(duration: 0.2), value: showCompleted)
                                }
                            }

                            if showCompleted {
                                VStack(spacing: PerchTheme.Spacing.medium) {
                                    ForEach(completedDeliveries) { record in
                                        if let delivery = record.asDelivery() {
                                            DeliveryCard(delivery: delivery)
                                                .contextMenu {
                                                    Button {
                                                        Task { await viewModel.togglePin(recordId: record.id) }
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
                await viewModel.refresh()
                PerchHaptics.success()
            }
        }
        .task {
            await viewModel.loadRecords()
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text("No deliveries")
                    .font(PerchTheme.Font.headline)
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
}
