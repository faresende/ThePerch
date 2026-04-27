import SwiftUI

struct OrderCard: View {
    @Environment(\.perchPalette) private var palette

    @Environment(\.openURL) private var openURL

    let model: OrderWithShipments
    /// Whether the items section is expanded. Owned by the parent
    /// (OrdersView) so only one card can be expanded at a time —
    /// mirrors the workout-card pattern in WorkoutView.swift.
    var isExpanded: Bool = false
    /// Called when the user long-presses and selects "Mark as Delivered".
    var onMarkDelivered: (() -> Void)?
    /// Called when the user long-presses and selects "Undo Delivery Override".
    var onUndoDelivered: (() -> Void)?

    /// Phase 1 corrections: long-press exposes "Why this is an order?"
    /// which presents the parse_trace debug sheet. State here, sheet
    /// rendered via .sheet modifier on the card body.
    @State private var showingParseTrace = false

    private let steps: [(key: String, label: String)] = [
        ("ordered", "Ordered"),
        ("shipped", "Shipped"),
        ("in_transit", "In Transit"),
        ("delivered", "Delivered"),
    ]

    private var primaryShipment: Shipment? {
        model.primaryShipment
    }

    private var statusPresentation: OrderStatusPresentation {
        statusPresentation(for: model.effectiveStatus)
    }

    private var activeStepIndex: Int {
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

    private var trackingReferenceDisplay: String? {
        guard let trackingNumber = primaryShipment?.trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines),
              !trackingNumber.isEmpty else {
            return nil
        }

        if trackingNumber.count > 12 {
            return "#" + String(trackingNumber.suffix(8))
        }

        return trackingNumber
    }

    private var shipmentLine: String? {
        guard let primaryShipment else { return nil }

        let shipmentStatus = statusPresentation(for: primaryShipment.status)
        let parts = [
            primaryShipment.carrier.isEmpty ? nil : primaryShipment.carrier,
            trackingReferenceDisplay,
            shipmentStatus.label,
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var shipmentAccessibilityLine: String? {
        guard let primaryShipment else { return nil }

        let shipmentStatus = statusPresentation(for: primaryShipment.status)
        let parts = [
            primaryShipment.carrier.isEmpty ? nil : primaryShipment.carrier,
            primaryShipment.trackingNumber.isEmpty ? nil : primaryShipment.trackingNumber,
            shipmentStatus.label,
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private var trackingURL: URL? {
        primaryShipment?.resolvedTrackingURL
    }

    private var hasActionMenu: Bool {
        if model.order.isManuallyDelivered {
            return onUndoDelivered != nil
        }
        return onMarkDelivered != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            header

            shipmentSummary

            manualOverrideBadge

            Rectangle()
                .fill(palette.line.opacity(0.7))
                .frame(height: 1)

            timeline

            // Expanded section — items list + order metadata. Reveals
            // when the parent flips `isExpanded` (workout-card pattern).
            // Hidden entirely when there are no items to show, to avoid
            // a useless empty section taking up vertical space.
            if isExpanded && !model.items.isEmpty {
                Rectangle()
                    .fill(palette.line.opacity(0.5))
                    .frame(height: 1)
                    .padding(.top, 2)

                expandedItemsSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .contextMenu {
            // hasActionMenu only gates Mark/Undo Delivered visibility;
            // "Why this is an order?" is always shown so the trace peek
            // is reachable on every card. Splitting the gate keeps the
            // legacy hasActionMenu logic intact for the delivery items.
            contextMenuItems
        }
        .sheet(isPresented: $showingParseTrace) {
            ParseTraceSheet(
                orderId: model.id,
                orderMerchant: model.order.merchant
            )
        }
    }

    /// Items list + per-line breakdown. Shown only when the card is
    /// expanded. Each row is name on the left, qty × unit price on the
    /// right. Mono pricing on the right keeps the column visually
    /// aligned even with mixed-length names.
    @ViewBuilder
    private var expandedItemsSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("ITEMS")
                    .font(PerchTheme.Font.cardEyebrow)
                    .foregroundColor(palette.muted)
                Spacer()
                Text("\(model.items.count)")
                    .font(PerchTheme.Font.microNumeric)
                    .foregroundColor(palette.faint)
            }

            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                ForEach(model.items) { item in
                    HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
                        Text("\(item.displayQuantity)×")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(palette.muted)
                            .frame(width: 28, alignment: .leading)

                        Text(item.name)
                            .font(.system(size: 14, weight: .regular, design: .serif).italic())
                            .foregroundColor(palette.ink)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !item.displayUnitPrice.isEmpty {
                            Text(item.displayUnitPrice)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(palette.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if !orderNumberDisplay.isEmpty {
                HStack {
                    Text("ORDER #")
                        .font(.system(size: 10))
                        .tracking(0.6)
                        .foregroundColor(palette.faint)
                    Text(orderNumberDisplay)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(palette.muted)
                    Spacer()
                }
                .padding(.top, PerchTheme.Spacing.xxxSmall)
            }
        }
    }

    /// Order number formatted for the expanded view. Empty string when
    /// the order has no captured number (e.g. user-confirmed review item).
    private var orderNumberDisplay: String {
        let n = model.order.orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "" : "#\(n)"
    }

    private var header: some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(statusPresentation.tint.opacity(0.14))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: statusPresentation.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(statusPresentation.tint)
                )

            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxxSmall) {
                // Linen-spec hierarchy: merchant is the editorial hero
                // (large serif italic, ink-colored), total sits quietly
                // underneath in a small muted mono. Color carries weight,
                // so the previous kinetic-orange total visually
                // dominated the dark-ink merchant heading even though
                // the merchant was technically the bigger font; flipping
                // the colors + bumping the size puts the merchant first.
                Text(model.order.merchant)
                    .font(.system(size: 22, weight: .semibold, design: .serif).italic())
                    .foregroundColor(palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)

                Text(totalText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(palette.muted)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: PerchTheme.Spacing.xxSmall) {
                statusBadge

                if let statusDateText {
                    Text(statusDateText)
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(palette.faint)
                }

                // Chevron is the discoverability hint that the card
                // expands. Only shown when there are items to reveal —
                // a card with no items has nothing to expand into.
                if !model.items.isEmpty {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(palette.faint)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 2)
                }
            }
        }
    }

    private var statusBadge: some View {
        Text(statusPresentation.label)
            .font(PerchTheme.Font.micro)
            .fontWeight(.semibold)
            .foregroundColor(statusBadgeForeground)
            .padding(.horizontal, PerchTheme.Spacing.small)
            .padding(.vertical, PerchTheme.Spacing.xxxSmall)
            .background(statusBadgeBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(statusBadgeBorder, lineWidth: 1)
            )
    }

    private var statusBadgeForeground: Color {
        switch normalizedStatus(model.effectiveStatus) {
        case "ordered", "shipped", "in_transit":
            return palette.heroText
        default:
            return statusPresentation.tint
        }
    }

    private var statusBadgeBackground: Color {
        switch normalizedStatus(model.effectiveStatus) {
        case "in_transit":
            return palette.kinetic.opacity(0.12)
        case "delivered":
            return palette.wellness.opacity(0.12)
        case "exception", "needs_review", "issue":
            return palette.error.opacity(0.12)
        default:
            return palette.kinetic.opacity(0.12)
        }
    }

    private var statusBadgeBorder: Color {
        switch normalizedStatus(model.effectiveStatus) {
        case "in_transit":
            return palette.kinetic.opacity(0.3)
        case "delivered":
            return palette.wellness.opacity(0.24)
        case "exception", "needs_review", "issue":
            return palette.error.opacity(0.22)
        default:
            return palette.kinetic.opacity(0.18)
        }
    }

    private var statusDateText: String? {
        let date = model.displayDate
        let shortDate = PerchFormatters.shortDate.string(from: date)

        if model.order.isManuallyDelivered {
            return "Marked \(shortDate)"
        }

        switch normalizedStatus(model.effectiveStatus) {
        case "delivered":
            return "Delivered \(shortDate)"
        case "ordered":
            return "Added \(shortDate)"
        case "shipped":
            return "Shipped \(shortDate)"
        case "in_transit":
            return "In Transit \(shortDate)"
        default:
            return "Added \(shortDate)"
        }
    }

    @ViewBuilder
    private var shipmentSummary: some View {
        if let shipmentLine {
            if let trackingURL {
                Button {
                    openURL(trackingURL)
                } label: {
                    shipmentSummaryContent(shipmentLine: shipmentLine, isTrackable: true)
                }
                .buttonStyle(CardPressStyle())
                .accessibilityLabel("Shipment \(shipmentAccessibilityLine ?? shipmentLine), opens tracking in browser")
            } else {
                shipmentSummaryContent(shipmentLine: shipmentLine, isTrackable: false)
            }
        }
    }

    private func shipmentSummaryContent(shipmentLine: String, isTrackable: Bool) -> some View {
        HStack(alignment: .center, spacing: PerchTheme.Spacing.small) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.kinetic.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: isTrackable ? "arrow.triangle.branch" : "shippingbox")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.kinetic)
                )

            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxxSmall) {
                Text(isTrackable ? "Tracking" : "Shipment")
                    .font(PerchTheme.Font.micro)
                    .fontWeight(.medium)
                    .foregroundColor(palette.muted)

                Text(shipmentLine)
                    .font(PerchTheme.Font.caption)
                    .fontWeight(.medium)
                    .foregroundColor(palette.ink)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if isTrackable {
                HStack(spacing: PerchTheme.Spacing.xxxSmall) {
                    Text("Track")
                        .font(PerchTheme.Font.micro)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.up.right.square")
                        .font(PerchTheme.Font.micro)
                        .fontWeight(.bold)
                }
                .foregroundColor(palette.kinetic)
            }
        }
        .padding(PerchTheme.Spacing.small)
        .background(palette.chipBg)
        .cornerRadius(PerchTheme.Card.innerCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                .stroke(isTrackable ? palette.kinetic.opacity(0.18) : palette.line.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if model.order.isManuallyDelivered {
            if onUndoDelivered != nil {
                Button(role: .destructive) {
                    onUndoDelivered?()
                } label: {
                    Label("Undo Delivery Override", systemImage: "clock.arrow.circlepath")
                }
            }
        } else {
            if onMarkDelivered != nil {
                Button {
                    onMarkDelivered?()
                } label: {
                    Label("Mark as Delivered", systemImage: "checkmark.circle.fill")
                }
            }
        }

        // Phase 1 corrections-and-rules: parse-trace debug peek.
        // Always available (works on Active / Issues / Delivered alike,
        // unlike the swipe affordance which is Active-only). Legacy
        // rows without a trace get a friendly empty state.
        Button {
            showingParseTrace = true
        } label: {
            Label("Why this is an order?", systemImage: "questionmark.circle")
        }
    }

    // MARK: - Manual override badge

    @ViewBuilder
    private var manualOverrideBadge: some View {
        if model.order.isManuallyDelivered {
            HStack(spacing: PerchTheme.Spacing.xxxSmall) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 10, weight: .medium))
                Text("Manual override")
                    .font(PerchTheme.Font.micro)
                    .fontWeight(.semibold)
            }
            .foregroundColor(palette.muted)
            .padding(.horizontal, PerchTheme.Spacing.small)
            .padding(.vertical, PerchTheme.Spacing.xxxSmall)
            .background(palette.muted.opacity(0.10))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(palette.line.opacity(0.55), lineWidth: 1)
            )
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.xxSmall) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let state = timelineState(for: index)

                VStack(spacing: PerchTheme.Spacing.xSmall) {
                    timelineMarker(for: step.key, state: state)

                    Text(step.label)
                        .font(PerchTheme.Font.micro)
                        .fontWeight(state == .current ? .semibold : .regular)
                        .foregroundColor(timelineLabelColor(for: state))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
                }
                .frame(maxWidth: .infinity)

                if index < steps.count - 1 {
                    Capsule()
                        .fill(timelineConnectorColor(after: index))
                        .frame(width: 18, height: 2)
                        .padding(.top, 5)
                }
            }
        }
    }

    private func timelineState(for index: Int) -> TimelineStepState {
        if index < activeStepIndex {
            return .completed
        }
        if index == activeStepIndex {
            return .current
        }
        return .upcoming
    }

    @ViewBuilder
    private func timelineMarker(for stepKey: String, state: TimelineStepState) -> some View {
        let accent = timelineColor(for: stepKey)

        switch state {
        case .completed:
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
        case .current:
            Circle()
                .fill(palette.card)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(accent, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                )
        case .upcoming:
            Circle()
                .fill(palette.card)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(palette.line.opacity(0.95), lineWidth: 1.5)
                )
        }
    }

    private func timelineLabelColor(for state: TimelineStepState) -> Color {
        switch state {
        case .current:
            return palette.ink
        case .completed:
            return palette.muted
        case .upcoming:
            return palette.faint
        }
    }

    private func timelineConnectorColor(after stepIndex: Int) -> Color {
        guard stepIndex < activeStepIndex else {
            return palette.line.opacity(0.9)
        }

        if stepIndex + 1 == activeStepIndex {
            return timelineColor(for: steps[activeStepIndex].key)
        }

        return palette.kinetic
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

    private func statusPresentation(for status: String) -> OrderStatusPresentation {
        switch status.lowercased() {
        case "delivered":
            return OrderStatusPresentation(label: "Delivered", symbol: "checkmark.circle.fill", tint: palette.wellness)
        case "in_transit", "out_for_delivery":
            return OrderStatusPresentation(label: "In Transit", symbol: "truck.box.fill", tint: palette.kinetic)
        case "shipped", "label_created":
            return OrderStatusPresentation(label: "Shipped", symbol: "shippingbox.fill", tint: palette.kinetic)
        case "exception", "needs_review", "issue":
            return OrderStatusPresentation(label: "Needs Review", symbol: "exclamationmark.triangle.fill", tint: palette.error)
        default:
            return OrderStatusPresentation(label: "Ordered", symbol: "cart.fill", tint: palette.kinetic)
        }
    }

    private func timelineColor(for status: String) -> Color {
        switch normalizedStatus(status) {
        case "delivered":
            return palette.wellness
        case "in_transit":
            return palette.kinetic
        default:
            return palette.kinetic
        }
    }

    private var accessibilitySummary: String {
        var summary = "\(model.order.merchant) order \(model.order.orderNumber), \(totalText)"
        let shipmentSummaryText = shipmentAccessibilityLine ?? shipmentLine
        if let shipmentSummaryText {
            summary += ", shipment \(shipmentSummaryText)"
            if trackingURL != nil {
                summary += ", tracking available in browser"
            }
        }
        summary += ", status \(statusPresentation.label)"
        if model.order.isManuallyDelivered {
            summary += ", manually marked as delivered"
        }
        return summary
    }
}

private struct OrderStatusPresentation {
    let label: String
    let symbol: String
    let tint: Color
}

private enum TimelineStepState {
    case completed
    case current
    case upcoming
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
        confidence: 0.85,
        createdAt: .now,
        manualDeliveredAt: .now
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
        OrderCard(
            model: OrderWithShipments(order: order, shipments: [shipment]),
            onMarkDelivered: { print("Mark delivered tapped") }
        )
        OrderCard(
            model: OrderWithShipments(order: manualOrder, shipments: []),
            onUndoDelivered: { print("Undo tapped") }
        )
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
}
