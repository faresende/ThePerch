import SwiftUI

/// Reusable section header with title and data freshness indicator.
/// Shows "Last updated: X min ago" and a subtle stale indicator when data is >5 min old.
struct SectionHeader: View {
    let title: String
    let freshnessKey: String

    private let freshnessTracker = DataFreshnessTracker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
            Text(title)
                .font(PerchTheme.Font.largeTitle)
                .foregroundColor(PerchTheme.textPrimary)

            HStack(spacing: 6) {
                if let timeStr = freshnessTracker.relativeTimeString(for: freshnessKey) {
                    if freshnessTracker.isStale(freshnessKey) {
                        // Stale indicator
                        Circle()
                            .fill(PerchTheme.warning)
                            .frame(width: 6, height: 6)
                    }
                    Text(timeStr)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(
                            freshnessTracker.isStale(freshnessKey)
                                ? PerchTheme.warning
                                : PerchTheme.textTertiary
                        )
                }
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        SectionHeader(title: "Deliveries", freshnessKey: "deliveries")
        SectionHeader(title: "Health", freshnessKey: "health")
    }
    .padding()
    .background(PerchTheme.background)
}
