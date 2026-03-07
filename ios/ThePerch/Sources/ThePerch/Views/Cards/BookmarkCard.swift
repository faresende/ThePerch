import SwiftUI

/// Displays an individual bookmark with favicon, title, domain, reading time, and tags.
/// Matches the React BookmarkCard design.
struct BookmarkCard: View {
    let bookmark: BookmarkData
    let onTap: (() -> Void)?

    var domainInitial: String {
        (bookmark.domain ?? "W").prefix(1).uppercased()
    }

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
                // Favicon / initial
                RoundedRectangle(cornerRadius: 10)
                    .fill(PerchTheme.accentMuted)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(domainInitial)
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.accent)
                    )

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Title (2 lines max)
                    Text(bookmark.displayTitle)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Domain + reading time
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Text(bookmark.domain ?? "Unknown")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)

                        if let readingTime = bookmark.readingTimeMinutes {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(PerchTheme.Font.micro)
                                Text("\(readingTime) min")
                                    .font(PerchTheme.Font.micro)
                            }
                            .foregroundColor(PerchTheme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PerchTheme.textSecondary.opacity(0.12))
                            .cornerRadius(6)
                        }
                    }

                    // Tags
                    if !bookmark.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(bookmark.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(PerchTheme.Font.micro)
                                    .foregroundColor(PerchTheme.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(PerchTheme.accentMuted)
                                    .cornerRadius(6)
                            }

                            if bookmark.tags.count > 3 {
                                Text("+\(bookmark.tags.count - 3)")
                                    .font(PerchTheme.Font.micro)
                                    .foregroundColor(PerchTheme.textTertiary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(PerchTheme.Card.padding + 4)
            .cardStyle()
        }
        .buttonStyle(CardPressStyle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: PerchTheme.Spacing.small) {
        BookmarkCard(
            bookmark: BookmarkData(
                url: "https://www.swiftui.dev/article/state-management",
                originalTitle: "SwiftUI State Management",
                enrichedTitle: "Understanding SwiftUI State Management",
                summary: "A comprehensive guide to managing state in SwiftUI.",
                tags: ["SwiftUI", "iOS", "State"],
                status: .processed,
                domain: "swiftui.dev",
                imageUrl: nil,
                readingTimeMinutes: 12,
                submittedFrom: "ios_share",
                processedAt: Date.now
            ),
            onTap: nil
        )

        BookmarkCard(
            bookmark: BookmarkData(
                url: "https://arxiv.org/paper",
                originalTitle: nil,
                enrichedTitle: nil,
                summary: nil,
                tags: [],
                status: .processing,
                domain: "arxiv.org",
                imageUrl: nil,
                readingTimeMinutes: nil,
                submittedFrom: "ios_share",
                processedAt: nil
            ),
            onTap: nil
        )
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
