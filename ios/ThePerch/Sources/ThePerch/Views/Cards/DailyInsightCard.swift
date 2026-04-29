import SwiftUI

/// Top-of-Today-tab card surfacing the day's BioChecha insight.
/// Editorial Linen treatment — small kicker, big serif italic body,
/// no chrome. The insight body is written by the agent in writerly
/// voice; the card just frames it cleanly.
///
/// Empty state (no insight yet): shown when BioChecha hasn't generated
/// today's row (typical pre-7am state). Quiet "checking back later"
/// line so the surface doesn't look broken.
struct DailyInsightCard: View {
    @Environment(\.perchPalette) private var palette

    let insight: Insight?

    var body: some View {
        if let insight {
            populated(insight)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func populated(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(insight.kicker)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.muted)

                Spacer()

                Text(formattedTime(insight.generatedAt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.faint)
            }

            // Body in serif italic — kept editorial in tone but smaller
            // than before so the card sits as one signal among many on
            // Today rather than dominating the tab. Was 18pt; 14pt
            // matches the visual weight of a typical card body line.
            Text(insight.body)
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.line.opacity(0.55), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(palette.muted.opacity(0.3))
                .frame(width: 6, height: 6)

            Text("The insight engine takes the morning to read your data. Today's insight will land here.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(palette.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.card.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.line.opacity(0.4), lineWidth: 1)
        )
    }

    private func formattedTime(_ date: Date) -> String {
        Self.shortTimeFormatter.string(from: date).lowercased()
    }

    /// Phase 3 perf: cached. Was created on every insight render.
    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

#Preview("Populated") {
    DailyInsightCard(insight: Insight(
        id: UUID(),
        userId: UUID(),
        agentId: "biochecha",
        insightType: "daily_health",
        title: nil,
        body: "Three short nights and HRV's been ducking. Lifting hard while light on sleep is the part you've been getting away with — until you don't. Today's a good candidate for a recovery day; if not, drop the volume.",
        data: nil,
        sourceRefs: nil,
        generatedAt: .now,
        validForDate: nil,
        shownAt: nil,
        dismissedAt: nil,
        pinned: false,
        expiresAt: nil
    ))
    .padding()
    .background(PerchTheme.background)
}

#Preview("Empty") {
    DailyInsightCard(insight: nil)
        .padding()
        .background(PerchTheme.background)
}
