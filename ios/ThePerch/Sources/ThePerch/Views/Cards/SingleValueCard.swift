import SwiftUI

/// Compact metric card matching the React MetricCard design.
/// Displays: source icon | label + value + unit | sparkline | trend arrow | timestamp
struct SingleValueCard: View {
    let value: String
    let label: String
    let unit: String?
    let trend: TrendIndicator?
    let lastUpdated: Date
    let sourceIcon: String?

    enum TrendIndicator {
        case up(Double)
        case down(Double)
        case neutral

        var icon: String {
            switch self {
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            case .neutral: return "arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .up: return PerchTheme.success
            case .down: return PerchTheme.error
            case .neutral: return PerchTheme.textSecondary
            }
        }

        var text: String {
            switch self {
            case .up(let percent):
                return "+\(String(format: "%.1f", percent))%"
            case .down(let percent):
                return "-\(String(format: "%.1f", percent))%"
            case .neutral:
                return "No change"
            }
        }
    }

    init(
        value: String,
        label: String,
        unit: String? = nil,
        trend: TrendIndicator? = nil,
        lastUpdated: Date,
        sourceIcon: String? = nil
    ) {
        self.value = value
        self.label = label
        self.unit = unit
        self.trend = trend
        self.lastUpdated = lastUpdated
        self.sourceIcon = sourceIcon
    }

    var body: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            // Source icon
            if let sourceIcon {
                Text(sourceIcon)
                    .font(.system(size: 20))
            }

            // Label + value + unit
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PerchTheme.textSecondary)

                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(PerchTheme.textPrimary)

                if let unit {
                    Text(unit)
                        .font(.system(size: 13))
                        .foregroundColor(PerchTheme.textSecondary)
                }
            }

            Spacer()

            // Trend arrow
            if let trend {
                Image(systemName: trend.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(trend.color)
            }

            // Timestamp
            Text(lastUpdated.relativeTime)
                .font(.system(size: 11))
                .foregroundColor(PerchTheme.textTertiary)
        }
        .padding(.horizontal, PerchTheme.Card.padding + 4)
        .padding(.vertical, 16)
        .cardStyle()
    }
}

extension Date {
    /// Returns a relative time string (e.g., "2 hours ago", "in 15m")
    var relativeTime: String {
        let interval = Date.now.timeIntervalSince(self)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 0 {
            // Future date
            let absMinutes = abs(minutes)
            let absHours = abs(hours)
            if absMinutes < 60 { return "in \(absMinutes)m" }
            if absHours < 24 { return "in \(absHours)h \(absMinutes % 60)m" }
            return "in \(abs(days))d"
        }
        if minutes < 1 {
            return "now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else if days < 7 {
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: self)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: PerchTheme.Spacing.small) {
        SingleValueCard(
            value: "81.5",
            label: "Weight",
            unit: "kg",
            trend: .down(2.3),
            lastUpdated: Date.now,
            sourceIcon: "❤️"
        )

        SingleValueCard(
            value: "72",
            label: "Heart Rate",
            unit: "bpm",
            trend: .neutral,
            lastUpdated: Date.now.addingTimeInterval(-3600),
            sourceIcon: "💓"
        )

        SingleValueCard(
            value: "$4.75",
            label: "Today's Cost",
            trend: .up(5.2),
            lastUpdated: Date.now.addingTimeInterval(-1800)
        )
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
