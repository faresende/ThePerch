import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text(title)
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(PerchTheme.Font.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PerchTheme.Spacing.medium)
                        .background(
                            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                .fill(PerchTheme.accent)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, PerchTheme.Spacing.xSmall)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PerchTheme.Spacing.xxLarge)
    }
}

#Preview {
    EmptyStateView(
        icon: "tray",
        title: "No data yet",
        subtitle: "Pull to refresh or try again in a moment.",
        actionTitle: "Refresh"
    ) {}
    .background(PerchTheme.background)
}
