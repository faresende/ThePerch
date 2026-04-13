import SwiftUI

struct OrderCard: View {
    let model: OrderWithShipments
    /// Called when the user long-presses and selects "Mark as Delivered".
    var onMarkDelivered: (() -> Void)?
    /// Called when the user long-presses and selects "Undo Delivery Override".
    var onUndoDelivered: (() -> Void)?

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
        // Use effectiveStatus so manually-overridden orders show the delivered step.
        let normalized = normalizedStatus(model.effectiveStatus)
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

            manualOverrideBadge

            timeline
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if model.order.isManuallyDelivered {
            // Offer undo when user previously set the override
            if onUndoDelivered != nil {
                Button(role: .destructive) {
                    onUndoDelivered?()
                } label: {
                    Label("Undo Delivery Override", systemImage: "clock.arrow.circlepath")
                }
            }
        } else {
            // Offer mark-as-delivered for untrackable shipments
            if onMarkDelivered != nil {
                Button {
                    onMarkDelivered?()
                } label: {
                    Label("Mark as Delivered", systemImage: "checkmark.circle.fill")
                }
            }
        }
    }

    // MARK: - Manual override badge

    @ViewBuilder
    private var manualOverrideBadge: some View {
        if model.order.isManuallyDelivered {
            HStack(spacing: PerchTheme.Spacing.xxxSmall) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 10, weight: .medium))
                Text("Manually marked delivered")
                    .font(PerchTheme.Font.micro)
            }
            .foregroundColor(PerchTheme.success)
            .padding(.horizontal, PerchTheme.Spacing.small)
            .padding(.vertical, PerchTheme.Spacing.xxxSmall)
            .background(PerchTheme.success.opacity(0.12))
            .cornerRadius(PerchTheme.Card.innerCornerRadius)
        }
    }

    // MARK: - Timeline

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
        summary += ", status \(stepTitle(for: model.effectiveStatus))"
        if model.order.isManuallyDelivered {
            summary += ", manually marked as delivered"
        }
        return summary
    }
}

#Preview {
    let orderId = UUID()
    let order = Order(
        id: orderId,
        merchant: "Amazon",
        orderNumber: "112-1234567-1234567",
        total: Decimal(string: "129.99"),
        currency: "USD",
        status: "shipped",
        sourceEmailId: "email_123",
        confidence: 0.92,
        createdAt: .now,
        manualDeliveredAt: nil
    )
    let manualOrder = Order(
        id: UUID(),
        merchant: "Zara",
        orderNumber: "ZR-9999",
        total: Decimal(string: "59.99"),
        currency: "EUR",
        status: "shipped",
        sourceEmailId: "email_456",
        confidence: 0.85,
        createdAt: .now,
        manualDeliveredAt: .now  // manually overridden
    )

    let shipment = Shipment(
        id: UUID(),
        orderId: orderId,
        trackingNumber: "1Z999AA10123456784",
        carrier: "UPS",
        status: "in_transit",
        createdAt: .now
    )

    return VStack(spacing: PerchTheme.Spacing.medium) {
        // Normal in-transit card with context menu callbacks
        OrderCard(
            model: OrderWithShipments(order: order, shipments: [shipment]),
            onMarkDelivered: { print("Mark delivered tapped") }
        )
        // Manually-overridden card showing badge + undo option
        OrderCard(
            model: OrderWithShipments(order: manualOrder, shipments: []),
            onUndoDelivered: { print("Undo tapped") }
        )
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
}
