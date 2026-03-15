import SwiftUI

/// Shows active deliveries as mini sub-cards within a single card.
/// Hides entirely when no active deliveries (no empty state).
struct DeliveryHomeCard: View {
    let records: [Record]

    private var latestUpdate: Date? {
        records
            .filter { $0.category == .deliveries && $0.type == .delivery }
            .map(\.updatedAt)
            .max()
    }

    private var activeDeliveries: [(record: Record, delivery: DeliveryData)] {
        records.compactMap { record -> (Record, DeliveryData)? in
            guard record.category == .deliveries,
                  record.type == .delivery,
                  let delivery = record.asDelivery() else { return nil }
            let status = delivery.status.lowercased().replacingOccurrences(of: " ", with: "_")
            guard status != "delivered" && status != "cancelled" else { return nil }
            return (record, delivery)
        }
    }

    var body: some View {
        if activeDeliveries.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                // Header
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Image(systemName: "shippingbox.fill")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.accent)
                    Text("DELIVERIES")
                        .font(PerchTheme.Font.cardEyebrow)
                        .foregroundColor(PerchTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                    CardFreshnessLabel(date: latestUpdate)
                    Text("\(activeDeliveries.count) active")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }

                // Delivery sub-cards
                ForEach(activeDeliveries, id: \.record.id) { item in
                    deliverySubCard(delivery: item.delivery)
                }
            }
            .padding(PerchTheme.Card.padding)
            .cardStyle()
        }
    }

    // MARK: - Sub-card

    private func deliverySubCard(delivery: DeliveryData) -> some View {
        let status = delivery.status.lowercased().replacingOccurrences(of: " ", with: "_")
        let isOutForDelivery = status == "out_for_delivery"

        return VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
            HStack(spacing: PerchTheme.Spacing.small) {
                // Status badge
                statusBadge(status: status)

                Spacer()

                // ETA
                if let eta = delivery.eta {
                    Text("ETA \(PerchFormatters.shortDate.string(from: eta))")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.accent)
                }
            }

            HStack(spacing: PerchTheme.Spacing.xSmall) {
                // Carrier
                Text(delivery.carrier)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)

                // Truncated tracking number
                if !delivery.trackingNumber.isEmpty {
                    Text("•")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                    Text("#\(String(delivery.trackingNumber.suffix(6)))")
                        .font(PerchTheme.Font.microMono)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }

            // Items summary
            let itemNames = delivery.items.map(\.name).joined(separator: ", ")
            if !itemNames.isEmpty {
                Text(itemNames)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(PerchTheme.Spacing.small)
        .background(PerchTheme.cardInnerBackground)
        .cornerRadius(PerchTheme.Card.innerCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                .stroke(
                    isOutForDelivery ? PerchTheme.success.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    @State private var isPulsing = false

    // MARK: - Status Badge

    private func statusBadge(status: String) -> some View {
        let (label, color) = statusInfo(status)
        let isOutForDelivery = status == "out_for_delivery"

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .scaleEffect(isOutForDelivery && isPulsing ? 1.3 : 1.0)
                .animation(
                    isOutForDelivery && !PerchMotion.prefersReduced
                        ? .easeInOut(duration: 2).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
            Text(label)
                .font(PerchTheme.Font.caption)
                .foregroundColor(color)
                .fontWeight(.medium)
        }
        .padding(.horizontal, PerchTheme.Spacing.xSmall)
        .padding(.vertical, PerchTheme.Spacing.xxxSmall)
        .background(color.opacity(0.12))
        .cornerRadius(8)
        .onAppear {
            if isOutForDelivery { isPulsing = true }
        }
    }

    private func statusInfo(_ status: String) -> (String, Color) {
        switch status {
        case "ordered", "pending":
            return ("Ordered", PerchTheme.textTertiary)
        case "shipped", "processing":
            return ("Shipped", PerchTheme.accent)
        case "in_transit":
            return ("In Transit", PerchTheme.warning)
        case "out_for_delivery":
            return ("Out for Delivery", PerchTheme.success)
        default:
            return (status.capitalized, PerchTheme.textTertiary)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DeliveryHomeCard(records: [])
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
