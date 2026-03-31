import SwiftUI

struct UniversalCardHeader: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let isPinned: Bool

    var body: some View {
        HStack(alignment: .top, spacing: PerchTheme.HomeCard.rowSpacing) {
            if let icon {
                Image(systemName: icon)
                    .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                    .foregroundColor(PerchTheme.accent)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxxSmall) {
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
