import SwiftUI

/// Displays delivery tracking with a horizontal step progress indicator.
/// Matches the React DeliveryCard design with dots and connector lines.
struct DeliveryCard: View {
    let delivery: DeliveryData
    let emoji: String

    @State private var animateTimeline = false

    init(delivery: DeliveryData, emoji: String = "📦") {
        self.delivery = delivery
        self.emoji = emoji
    }

    private let steps: [(key: String, label: String)] = [
        ("ordered", "Ordered"),
        ("shipped", "Shipped"),
        ("out_for_delivery", "Out"),
        ("delivered", "Delivered"),
    ]

    private var activeIndex: Int {
        let statusKey = delivery.status.lowercased().replacingOccurrences(of: " ", with: "_")
        // Map common API status values to step keys
        let normalizedKey: String
        switch statusKey {
        case "in_transit", "shipped", "processing":
            normalizedKey = "shipped"
        case "out_for_delivery":
            normalizedKey = "out_for_delivery"
        case "delivered":
            normalizedKey = "delivered"
        case "pending", "ordered":
            normalizedKey = "ordered"
        default:
            normalizedKey = statusKey
        }
        return steps.firstIndex(where: { $0.key == normalizedKey }) ?? 0
    }

    private var etaFormatted: String? {
        guard let eta = delivery.eta else { return nil }
        return PerchFormatters.shortDate.string(from: eta)
    }

    private var trackingSuffix: String? {
        guard !delivery.trackingNumber.isEmpty else { return nil }
        return "#" + String(delivery.trackingNumber.suffix(6))
    }

    private var hasTrackingUrl: Bool {
        guard let url = delivery.trackingUrl, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }

    var body: some View {
        Button(action: openTracking) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    // Emoji icon
                    RoundedRectangle(cornerRadius: 10)
                        .fill(PerchTheme.accentMuted)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(emoji)
                                .font(PerchTheme.Font.title)
                        )

                    // Item name + carrier
                    VStack(alignment: .leading, spacing: 3) {
                        Text(delivery.items.first?.name ?? "Package")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(delivery.carrier)
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)

                            if let suffix = trackingSuffix {
                                Text(suffix)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textTertiary)
                            }
                        }
                    }

                    Spacer()

                    // ETA badge + tracking indicator
                    VStack(alignment: .trailing, spacing: 4) {
                        if let eta = etaFormatted {
                            Text("ETA \(eta)")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.accent)
                        }
                        if hasTrackingUrl {
                            HStack(spacing: 3) {
                                Text("Track")
                                    .font(PerchTheme.Font.micro)
                                Image(systemName: "arrow.up.right")
                                    .font(PerchTheme.Font.micro)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(PerchTheme.textTertiary)
                        }
                    }
                }

                // Progress stepper
                progressStepper
            }
            .padding(PerchTheme.Spacing.large)
            .cardStyle()
        }
        .buttonStyle(CardPressStyle())
        .deliveryCompletionCelebration(isDelivered: activeIndex == steps.count - 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .onAppear {
            PerchMotion.withOptionalAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                animateTimeline = true
            }
        }
    }

    private func openTracking() {
        if let urlStr = delivery.trackingUrl, let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }

    private var progressStepper: some View {
        GeometryReader { geometry in
            let stepCount = CGFloat(steps.count)
            let dotSize: CGFloat = 18       // 50% larger (was 12)
            let activeDotSize: CGFloat = 24  // 50% larger (was 16)
            let maxDot = activeDotSize
            let totalWidth = geometry.size.width - maxDot
            let stepSpacing = totalWidth / (stepCount - 1)
            let lineY: CGFloat = maxDot / 2  // center line on largest dot

            ZStack(alignment: .topLeading) {
                // Connector line (background)
                Path { path in
                    path.move(to: CGPoint(x: maxDot / 2, y: lineY))
                    path.addLine(to: CGPoint(x: totalWidth + maxDot / 2, y: lineY))
                }
                .stroke(PerchTheme.border, lineWidth: 3)

                // Connector line (active portion) — animated
                if activeIndex > 0 {
                    let activeWidth = stepSpacing * CGFloat(activeIndex)
                    Path { path in
                        path.move(to: CGPoint(x: maxDot / 2, y: lineY))
                        path.addLine(to: CGPoint(x: (animateTimeline ? activeWidth : 0) + maxDot / 2, y: lineY))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [PerchTheme.accent.opacity(0.7), PerchTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 3
                    )
                }

                // Step dots with icons and labels
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    let isComplete = index <= activeIndex
                    let isCurrent = index == activeIndex
                    let x = stepSpacing * CGFloat(index) + maxDot / 2
                    let size = isCurrent ? activeDotSize : dotSize
                    let stepIcon = stepSystemImage(for: step.key)

                    // Dot with icon — vertically centered on the connector line
                    ZStack {
                        Circle()
                            .fill(isComplete ? PerchTheme.accent : PerchTheme.border)
                            .frame(width: size, height: size)
                            .shadow(
                                color: isCurrent ? PerchTheme.accent.opacity(0.5) : .clear,
                                radius: isCurrent ? 8 : 0
                            )

                        if isCurrent || isComplete {
                            Image(systemName: stepIcon)
                                .font(PerchTheme.Font.micro)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                        }
                    }
                    .position(x: x, y: lineY)
                    .opacity(animateTimeline || index == 0 ? 1 : (isComplete ? 1 : 0.5))

                    // Label — positioned below the dot
                    Text(step.label)
                        .font(PerchTheme.Font.micro)
                        .fontWeight(isCurrent ? .bold : .regular)
                        .foregroundColor(isComplete ? PerchTheme.textPrimary : PerchTheme.textTertiary)
                        .frame(width: 60)
                        .position(x: x, y: lineY + maxDot / 2 + 14)
                }
            }
        }
        .frame(height: 60)
        .padding(.horizontal, PerchTheme.Spacing.xxSmall)
    }

    private var accessibilitySummary: String {
        let itemName = delivery.items.first?.name ?? "Package"
        let status = steps[activeIndex].label.lowercased()
        var summary = "Delivery: \(itemName) via \(delivery.carrier), \(status)"
        if let eta = etaFormatted {
            summary += ", arriving \(eta)"
        }
        return summary
    }

    private func stepSystemImage(for key: String) -> String {
        switch key {
        case "ordered": return "cart.fill"
        case "shipped": return "shippingbox.fill"
        case "out_for_delivery": return "truck.box.fill"
        case "delivered": return "checkmark"
        default: return "circle.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: PerchTheme.Spacing.medium) {
        DeliveryCard(
            delivery: DeliveryData(
                orderId: "12345",
                carrier: "DHL Express",
                trackingNumber: "DHL1234567890",
                status: "in_transit",
                eta: Date.now.addingTimeInterval(86400 * 2),
                items: [DeliveryItem(name: "Wireless Headphones", quantity: 1, description: nil)],
                trackingUrl: nil
            )
        )

        DeliveryCard(
            delivery: DeliveryData(
                orderId: "67890",
                carrier: "Correios",
                trackingNumber: "BR9876543210",
                status: "out_for_delivery",
                eta: Date.now.addingTimeInterval(3600),
                items: [DeliveryItem(name: "LED Desk Lamp", quantity: 1, description: nil)],
                trackingUrl: nil
            )
        )
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
