import SwiftUI

/// Displays an ordered list of status items with icon, title, status badge, and timestamp.
/// Good for: delivery tracking, agent status.
struct StatusListCard: View {
    let items: [StatusItem]

    struct StatusItem: Identifiable {
        let id: UUID
        let icon: String
        let title: String
        let status: String
        let statusColor: Color
        let timestamp: Date
        let onTap: (() -> Void)?

        init(
            id: UUID = UUID(),
            icon: String,
            title: String,
            status: String,
            statusColor: Color,
            timestamp: Date,
            onTap: (() -> Void)? = nil
        ) {
            self.id = id
            self.icon = icon
            self.title = title
            self.status = status
            self.statusColor = statusColor
            self.timestamp = timestamp
            self.onTap = onTap
        }
    }

    var body: some View {
        CardContainer {
            VStack(spacing: PerchTheme.Spacing.xSmall) {
                ForEach(items) { item in
                    StatusItemRow(item: item)
                }
            }
        }
    }
}

// MARK: - Status Item Row

struct StatusItemRow: View {
    let item: StatusListCard.StatusItem

    var body: some View {
        Button(action: { item.onTap?() }) {
            HStack(spacing: PerchTheme.Spacing.small) {
                // Icon
                Image(systemName: item.icon)
                    .font(.system(size: PerchTheme.Icon.medium))
                    .foregroundColor(PerchTheme.accent)
                    .frame(width: PerchTheme.Icon.large)

                // Title and status
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                    Text(item.title)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(1)

                    Text(item.timestamp.relativeTime)
                        .font(PerchTheme.Font.caption2)
                        .foregroundColor(PerchTheme.textTertiary)
                }

                Spacer()

                // Status badge
                HStack(spacing: PerchTheme.Spacing.xxSmall) {
                    Text(item.status)
                        .font(PerchTheme.Font.caption1)
                        .foregroundColor(.white)
                        .padding(.horizontal, PerchTheme.Spacing.small)
                        .padding(.vertical, PerchTheme.Spacing.xxSmall)
                        .background(item.statusColor)
                        .cornerRadius(PerchTheme.Card.cornerRadius / 2)
                }
            }
            .padding(.vertical, PerchTheme.Spacing.small)
            .padding(.horizontal, PerchTheme.Spacing.xSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    StatusListCard(
        items: [
            StatusListCard.StatusItem(
                icon: "shippingbox.fill",
                title: "Wireless Headphones",
                status: "In Transit",
                statusColor: PerchTheme.accent,
                timestamp: Date.now.addingTimeInterval(-3600)
            ),
            StatusListCard.StatusItem(
                icon: "shippingbox.fill",
                title: "LED Desk Lamp",
                status: "Out for Delivery",
                statusColor: PerchTheme.warning,
                timestamp: Date.now.addingTimeInterval(-600)
            ),
            StatusListCard.StatusItem(
                icon: "checkmark.circle.fill",
                title: "USB-C Cable",
                status: "Delivered",
                statusColor: PerchTheme.success,
                timestamp: Date.now.addingTimeInterval(-86400)
            ),
        ]
    )
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
