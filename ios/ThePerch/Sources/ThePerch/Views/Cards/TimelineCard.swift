import SwiftUI

/// Displays chronological events in a vertical timeline with dots and connecting lines.
/// Good for: calendar events, activity log.
struct TimelineCard: View {
    let items: [TimelineItem]

    struct TimelineItem: Identifiable {
        let id: UUID
        let time: String
        let title: String
        let subtitle: String?

        init(
            id: UUID = UUID(),
            time: String,
            title: String,
            subtitle: String? = nil
        ) {
            self.id = id
            self.time = time
            self.title = title
            self.subtitle = subtitle
        }
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    TimelineItemRow(
                        item: item,
                        isLast: index == items.count - 1
                    )
                }
            }
        }
    }
}

// MARK: - Timeline Item Row

struct TimelineItemRow: View {
    let item: TimelineCard.TimelineItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            // Timeline line and dot
            VStack(spacing: 0) {
                // Dot
                Circle()
                    .fill(PerchTheme.accent)
                    .frame(width: 12, height: 12)

                // Connecting line (if not last)
                if !isLast {
                    VStack(spacing: 0) {
                        Divider()
                            .frame(height: 1)
                            .background(PerchTheme.border)
                    }
                    .frame(height: PerchTheme.Spacing.large + PerchTheme.Spacing.medium)
                }
            }
            .frame(width: 12)

            // Content
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                Text(item.time)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)

                Text(item.title)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textPrimary)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, PerchTheme.Spacing.small)
        }
    }
}

// MARK: - Preview

#Preview {
    TimelineCard(
        items: [
            TimelineCard.TimelineItem(
                time: "09:00 AM",
                title: "Team Standup",
                subtitle: "Conference Room A"
            ),
            TimelineCard.TimelineItem(
                time: "02:00 PM",
                title: "Client Meeting",
                subtitle: "Zoom call with stakeholders"
            ),
            TimelineCard.TimelineItem(
                time: "04:30 PM",
                title: "Project Review",
                subtitle: nil
            ),
        ]
    )
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
