import SwiftUI

/// Delivery tracking section with active and completed deliveries.
/// Uses the new DeliveryCard with horizontal step progress indicator.
struct DeliveriesView: View {
    @State private var viewModel = SectionViewModel(category: .deliveries)
    @State private var showCompleted = false

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
                ProgressView()
                    .tint(PerchTheme.accent)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Section header
                    Text("Deliveries")
                        .font(PerchTheme.Font.largeTitle)
                        .foregroundColor(PerchTheme.textPrimary)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    // Active deliveries
                    if !activeDeliveries.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Active Deliveries")
                                .font(PerchTheme.Font.headline)
                                .foregroundColor(PerchTheme.textPrimary)

                            VStack(spacing: PerchTheme.Spacing.medium) {
                                ForEach(activeDeliveries) { record in
                                    if let delivery = record.asDelivery() {
                                        DeliveryCard(delivery: delivery)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // Completed deliveries (collapsible)
                    if !completedDeliveries.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Button(action: { showCompleted.toggle() }) {
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
                await viewModel.refresh()
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
