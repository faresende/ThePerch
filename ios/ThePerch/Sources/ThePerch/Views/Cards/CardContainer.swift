import SwiftUI

/// A reusable card wrapper that provides consistent card styling.
/// Supports an optional header with title and icon, plus custom content.
struct CardContainer<Content: View>: View {
    let title: String?
    let icon: String?
    let content: Content

    init(
        title: String? = nil,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            // Header (if title or icon provided)
            if title != nil || icon != nil {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: PerchTheme.Icon.medium))
                            .foregroundColor(PerchTheme.accent)
                    }
                    if let title {
                        Text(title)
                            .font(PerchTheme.Font.headline)
                            .foregroundColor(PerchTheme.textPrimary)
                    }
                    Spacer()
                }
            }

            // Custom content
            content
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: PerchTheme.Spacing.medium) {
        CardContainer(title: "Weight", icon: "heart.fill") {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                Text("81.5 kg")
                    .font(PerchTheme.Font.title2)
                    .foregroundColor(PerchTheme.textPrimary)
                Text("Latest measurement")
                    .font(PerchTheme.Font.caption1)
                    .foregroundColor(PerchTheme.textSecondary)
            }
        }

        CardContainer {
            Text("Card without header")
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textSecondary)
        }
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
