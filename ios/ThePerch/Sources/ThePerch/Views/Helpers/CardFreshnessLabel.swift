import SwiftUI

enum CardFreshness {
    static func text(for date: Date) -> String {
        let interval = max(0, Date.now.timeIntervalSince(date))
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)

        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }

        let days = max(1, hours / 24)
        return "\(days)d ago"
    }

    static func color(for date: Date) -> Color {
        PerchTheme.textTertiary
    }
}

/// Displays a relative "Updated Xm ago" label for card freshness.
/// Uses a muted tertiary color to keep freshness labels visually secondary.
struct CardFreshnessLabel: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(CardFreshness.text(for: date))
                .font(PerchTheme.Font.micro)
                .foregroundColor(CardFreshness.color(for: date))
                .lineLimit(1)
        }
    }
}
