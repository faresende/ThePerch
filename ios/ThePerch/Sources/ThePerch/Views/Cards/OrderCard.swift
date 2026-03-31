import SwiftUI

struct OrderCard: View {
    let model: OrderWithShipments

    private let steps: [(key: String, label: String)] = [
        ("ordered", "Ordered"),
        ("shipped", "Shipped"),
        ("in_transit", "In Transit"),
        ("delivered", "Delivered"),
    ]

    private var primaryShipment: Shipment? {
        model.primaryShipment
    }

    private var activeStepIndex: Int {
        let normalized = normalizedStatus(model.displayStatus)
        return steps.firstIndex(where: { $0.key == normalized }) ?? 0
    }

    private var totalText: String {
        guard let total = model.order.total else { return "Total unavailable" }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = model.order.currency

        let amount = NSDecimalNumber(decimal: total)
        return formatter.string(from: amount) ?? "\(model.order.currency) \(amount)"
    }

    private var shipmentLine: String? {
        guard let primaryShipment else { return nil }

        let parts = [
            primaryShipment.carrier.isEmpty ? nil : primaryShipment.carrier,
            primaryShipment.trackingNumber.isEmpty ? nil : primaryShipment.trackingNumber,
            stepTitle(for: primaryShipment.status),
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                Text(model.order.merchant)
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)
                    .lineLimit(2)

                Text("Order \(model.order.orderNumber)")
                    .font(PerchTheme.Font.captionMono)
                    .foregroundColor(PerchTheme.textSecondary)

                Text(totalText)
                    .font(PerchTheme.Font.bodyNumeric)
                    .foregroundColor(PerchTheme.accent)
            }

            if let shipmentLine {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxxSmall) {
                    Text("Shipment")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                    Text(shipmentLine)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)
                        .lineLimit(2)
                }
                .padding(PerchTheme.Spacing.small)
                .background(PerchTheme.cardInnerBackground)
                .cornerRadius(PerchTheme.Card.innerCornerRadius)
            }

            timeline
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var timeline: some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.xSmall) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let isActive = index <= activeStepIndex
                let isCurrent = index == activeStepIndex

                VStack(spacing: PerchTheme.Spacing.xSmall) {
                    Circle()
                        .fill(isActive ? timelineColor(for: step.key) : PerchTheme.border)
                        .frame(width: isCurrent ? 14 : 10, height: isCurrent ? 14 : 10)
                        .overlay(
                            Circle()
                                .stroke(isCurrent ? timelineColor(for: step.key).opacity(0.35) : .clear, lineWidth: 4)
                        )

                    Text(step.label)
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(isActive ? PerchTheme.textPrimary : PerchTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(index < activeStepIndex ? PerchTheme.accent : PerchTheme.border)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 5)
                }
            }
        }
    }

    private func normalizedStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "ordered", "pending", "processing":
            return "ordered"
        case "shipped", "label_created":
            return "shipped"
        case "in_transit", "out_for_delivery":
            return "in_transit"
        case "delivered":
            return "delivered"
        default:
            return "ordered"
        }
    }

    private func stepTitle(for status: String) -> String {
        let normalized = normalizedStatus(status)
        return steps.first(where: { $0.key == normalized })?.label ?? status.capitalized
    }

    private func timelineColor(for status: String) -> Color {
        switch normalizedStatus(status) {
        case "delivered":
            return PerchTheme.success
        case "in_transit":
            return PerchTheme.warning
        default:
            return PerchTheme.accent
        }
    }

    private var accessibilitySummary: String {
        var summary = "\(model.order.merchant) order \(model.order.orderNumber), \(totalText)"
        if let shipmentLine {
            summary += ", shipment \(shipmentLine)"
        }
        summary += ", status \(stepTitle(for: model.displayStatus))"
        return summary
    }
}

#Preview {
    let order = Order(
        id: UUID(),
        merchant: "Amazon",
        orderNumber: "112-1234567-1234567",
        total: Decimal(string: "129.99"),
        currency: "USD",
        status: "shipped",
        sourceEmailId: "email_123",
        confidence: 0.92,
        createdAt: .now
    )

    let shipment = Shipment(
        id: UUID(),
        orderId: order.id,
        trackingNumber: "1Z999AA10123456784",
        carrier: "UPS",
        status: "in_transit",
        createdAt: .now
    )

    return VStack(spacing: PerchTheme.Spacing.medium) {
        OrderCard(model: OrderWithShipments(order: order, shipments: [shipment]))
        OrderCard(model: OrderWithShipments(order: order, shipments: []))
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
}
