import SwiftUI

/// Lists unresolved review items surfaced by the orders-autopilot classifier.
/// Presented as a sheet from OrdersView when at least one item is pending.
///
/// Each row shows the kind, reason, and suggested action. Users can dismiss
/// with a tap; the service soft-resolves (writes resolved_at) so nothing is
/// lost — the iOS list just stops showing them.
struct ReviewItemsView: View {
    @Bindable var viewModel: OrdersViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.reviewItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing to review",
                        systemImage: "checkmark.circle",
                        description: Text(
                            "The orders autopilot hasn't flagged anything. "
                            + "Items show up here when an email looks order-related "
                            + "but the classifier couldn't confidently link it to an order."
                        )
                    )
                } else {
                    List {
                        ForEach(viewModel.reviewItems) { item in
                            ReviewItemRow(item: item) {
                                Task { await viewModel.resolveReviewItem(item) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Review Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ReviewItemRow: View {
    let item: ReviewItem
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayKind)
                        .font(.subheadline.weight(.semibold))
                    Text(item.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(item.confidenceScore * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Confidence \(Int(item.confidenceScore * 100)) percent")
            }

            Text(item.reason)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let suggestion = item.suggestedAction, !suggestion.isEmpty {
                Text(suggestion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(role: .destructive, action: onDismiss) {
                    Label("Dismiss", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview {
    let vm = OrdersViewModel()
    vm.reviewItems = [
        ReviewItem(
            id: UUID(),
            userId: UUID(),
            type: "orphan_shipment",
            relatedOrderId: nil,
            relatedShipmentId: nil,
            reason: "Shipping notification email from noreply@dhl.com but no tracking number could be extracted.",
            suggestedAction: "Review the email and manually add tracking number if valid.",
            confidenceScore: 0.63,
            resolvedAt: nil,
            createdAt: Date().addingTimeInterval(-3600),
            updatedAt: Date().addingTimeInterval(-3600)
        ),
        ReviewItem(
            id: UUID(),
            userId: UUID(),
            type: "shipment_no_order",
            relatedOrderId: nil,
            relatedShipmentId: nil,
            reason: "Shipment with tracking 1Z999AA10123456785 (UPS) could not be matched to any order.",
            suggestedAction: "Link this shipment to the correct order or mark as standalone.",
            confidenceScore: 0.48,
            resolvedAt: nil,
            createdAt: Date().addingTimeInterval(-7200),
            updatedAt: Date().addingTimeInterval(-7200)
        ),
    ]
    return ReviewItemsView(viewModel: vm)
}
#endif
