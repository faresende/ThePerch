import SwiftUI

enum CardFreshness {
    static func text(for date: Date) -> String {
        let interval = max(0, Date.now.timeIntervalSince(date))
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)

        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes)m ago" }
        if hours < 24 { return "Updated \(hours)h ago" }

        let days = max(1, hours / 24)
        return "Updated \(days)d ago · Data may be outdated"
    }

    static func color(for date: Date) -> Color {
        let hours = Date.now.timeIntervalSince(date) / 3600
        if hours < 1 { return PerchTheme.textTertiary }
        if hours < 24 { return PerchTheme.warning }
        return PerchTheme.error
    }
}

/// Displays a relative "Updated Xm ago" label for card freshness.
/// Color adapts: tertiary for recent (<1h), amber for stale (1-24h), red for very stale (>24h).
struct CardFreshnessLabel: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(CardFreshness.text(for: date))
                .font(PerchTheme.Font.micro)
                .foregroundColor(CardFreshness.color(for: date))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}
