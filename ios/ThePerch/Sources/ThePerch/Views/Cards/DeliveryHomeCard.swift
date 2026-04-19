import SwiftUI

/// Shows active deliveries as mini sub-cards within a single card.
/// When nothing is in transit, shows a gentle empty-state illustration
/// plus a rotating phrase — the card stays part of the feed so the
/// dashboard reads consistently regardless of whether you have packages
/// on the way.
struct DeliveryHomeCard: View {
    let deliveries: [DeliveryData]

    private var activeDeliveries: [DeliveryData] {
        deliveries.filter { delivery in
            let status = delivery.status.lowercased().replacingOccurrences(of: " ", with: "_")
            return status != "delivered" && status != "cancelled"
        }
    }

    /// Rotating interpretive phrase — "Doorstep quiet", "A couple on the
    /// way", "Busy doorstep", etc. Keyed to today + count so it's stable
    /// within a day but varies day-over-day.
    private var deliveryPhrase: String {
        PerchPhrase.deliveryPhrase(count: activeDeliveries.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.HomeCard.verticalPadding) {
            // Header — always present so the card is recognisable even when
            // empty. Trailing text omitted in the empty state (phrase carries it).
            VStack(alignment: .leading, spacing: 4) {
                HomeCardHeader(
                    systemImage: "shippingbox.fill",
                    title: "DELIVERIES",
                    trailingText: activeDeliveries.isEmpty ? nil : "\(activeDeliveries.count) active"
                )

                Text(deliveryPhrase)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textPrimary)
            }

            if activeDeliveries.isEmpty {
                HStack {
                    Spacer()
                    Image("empty-deliveries")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 120)
                        .accessibilityLabel("Nothing in transit")
                    Spacer()
                }
                .padding(.vertical, PerchTheme.Spacing.xSmall)
            } else {
                // Delivery sub-cards
                ForEach(activeDeliveries, id: \.orderId) { delivery in
                    deliverySubCard(delivery: delivery)
                }
            }
        }
        .padding(.horizontal, PerchTheme.HomeCard.horizontalPadding)
        .padding(.vertical, PerchTheme.HomeCard.verticalPadding)
        .cardStyle()
    }

    // MARK: - Sub-card

    private func deliverySubCard(delivery: DeliveryData) -> some View {
        let status = delivery.status.lowercased().replacingOccurrences(of: " ", with: "_")
        let isOutForDelivery = status == "out_for_delivery"

        return VStack(alignment: .leading, spacing: PerchTheme.HomeCard.rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: PerchTheme.HomeCard.columnGutter) {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                    let itemNames = delivery.items.map(\.name).joined(separator: ", ")
                    if !itemNames.isEmpty {
                        Text(itemNames)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                            .lineLimit(1)
                    }

                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Text(delivery.carrier)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)

                        if !delivery.trackingNumber.isEmpty {
                            Text("•")
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.textTertiary)
                            Text("#\(String(delivery.trackingNumber.suffix(6)))")
                                .font(PerchTheme.Font.microMono)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }
                }
                .offset(x: -2)

                Spacer(minLength: PerchTheme.HomeCard.columnGutter)

                VStack(alignment: .trailing, spacing: PerchTheme.Spacing.xxSmall) {
                    statusBadge(status: status)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(x: PerchTheme.Spacing.xSmall)

                    if let eta = delivery.eta {
                        Text("ETA \(PerchFormatters.shortDate.string(from: eta))")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .offset(x: PerchTheme.Spacing.xSmall)
                    }
                }
                .frame(minWidth: PerchTheme.HomeCard.trailingColumnMinWidth, maxWidth: .infinity, alignment: .trailing)
            }

        }
        .homeCardItemStyle()
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

        return HStack(spacing: PerchTheme.Spacing.xxSmall) {
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, PerchTheme.Spacing.xSmall)
        .padding(.vertical, PerchTheme.Spacing.xxxSmall)
        .background(color.opacity(0.12))
        .cornerRadius(PerchTheme.Spacing.xSmall)
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
        DeliveryHomeCard(deliveries: [])
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
