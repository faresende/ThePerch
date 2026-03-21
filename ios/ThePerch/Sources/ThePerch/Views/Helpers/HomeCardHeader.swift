import SwiftUI

struct HomeCardHeader: View {
    let systemImage: String
    let title: String
    let trailingText: String?
    var showsChevron: Bool = false
    var isExpanded: Bool = true

    var body: some View {
        HStack(spacing: PerchTheme.Spacing.xSmall) {
            Image(systemName: systemImage)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.accent)

            Text(title)
                .font(PerchTheme.Font.cardEyebrow)
                .foregroundColor(PerchTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)

            Spacer(minLength: PerchTheme.HomeCard.columnGutter)

            if let trailingText {
                Text(trailingText)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if showsChevron {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(PerchTheme.textTertiary)
            }
        }
    }
}

private struct HomeCardRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, PerchTheme.HomeCard.rowVerticalPadding)
    }
}

private struct HomeCardItemModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PerchTheme.HomeCard.itemPadding)
            .background(PerchTheme.cardInnerBackground)
            .cornerRadius(PerchTheme.HomeCard.itemCornerRadius)
    }
}

extension View {
    func homeCardRowStyle() -> some View {
        modifier(HomeCardRowModifier())
    }

    func homeCardItemStyle() -> some View {
        modifier(HomeCardItemModifier())
    }
}
