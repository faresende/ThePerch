import SwiftUI

struct UniversalCardHeader: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let freshnessDate: Date?
    let isPinned: Bool

    var body: some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            if let icon {
                Image(systemName: icon)
                    .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                    .foregroundColor(PerchTheme.accent)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: PerchTheme.Spacing.xSmall) {
                    Text(title)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(2)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                            .accessibilityLabel("Pinned")
                    }

                    Spacer(minLength: 0)

                    if let freshnessDate {
                        Text(CardFreshness.text(for: freshnessDate))
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(CardFreshness.color(for: freshnessDate))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(CardFreshness.color(for: freshnessDate).opacity(0.12))
                            )
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel(CardFreshness.text(for: freshnessDate))
                    }
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
