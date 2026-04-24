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

    @Environment(\.perchPalette) private var palette

    var body: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 0) {
                TodayEyebrow(
                    label: "DELIVERIES · EN ROUTE",
                    accent: palette.kinetic,
                    freshness: activeDeliveries.isEmpty ? "—" : "\(activeDeliveries.count) active"
                )
                TodayPhrase(text: deliveryPhrase)

                if activeDeliveries.isEmpty {
                    HStack {
                        Spacer()
                        Image("empty-deliveries")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 130)
                            .accessibilityLabel("Nothing in transit")
                        Spacer()
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(activeDeliveries, id: \.orderId) { delivery in
                            deliverySubCard(delivery: delivery)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sub-card (Linen spec)
    //
    // [retailer badge 34×34, chipBg, first 3 letters]
    //   [item names] \n [tracking · status in mono]
    //                                              [ETA chip]
    // Out-for-delivery: row gets a chipBg background + radius-12 frame
    // with a 1px kinetic-tinted ring; the ETA chip becomes white-on-kinetic.

    private func deliverySubCard(delivery: DeliveryData) -> some View {
        let status = delivery.status.lowercased().replacingOccurrences(of: " ", with: "_")
        let isOutForDelivery = status == "out_for_delivery"
        let retailerCode = String(delivery.carrier.prefix(3)).uppercased()
        let itemNames = delivery.items.map(\.name).joined(separator: ", ")

        return HStack(alignment: .center, spacing: 12) {
            Text(retailerCode)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(palette.muted)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.chipBg)
                )

            VStack(alignment: .leading, spacing: 2) {
                if !itemNames.isEmpty {
                    Text(itemNames)
                        .font(PerchTheme.Font.bodyRow)
                        .foregroundColor(palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    if !delivery.trackingNumber.isEmpty {
                        Text(String(delivery.trackingNumber.suffix(8)))
                            .font(PerchTheme.Font.microNumeric)
                            .tracking(0.2)
                        Text("·")
                    }
                    Text(delivery.status)
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(palette.muted)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            TodayChip(
                text: etaText(delivery.eta),
                color: isOutForDelivery ? palette.heroText : palette.kinetic,
                background: isOutForDelivery ? palette.kinetic : palette.chipBg
            )
        }
        .padding(.horizontal, isOutForDelivery ? 12 : 0)
        .padding(.vertical, isOutForDelivery ? 10 : 0)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isOutForDelivery ? palette.chipBg : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isOutForDelivery ? palette.kinetic.opacity(0.18) : .clear, lineWidth: 1)
        )
    }

    private func etaText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return PerchFormatters.shortWeekdayUK.string(from: date)
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
