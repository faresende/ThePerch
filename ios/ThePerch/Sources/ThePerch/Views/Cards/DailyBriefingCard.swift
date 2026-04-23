import SwiftUI

/// Top-of-Today card showing BioChecha's morning briefing.
/// Reads the most recent `daily_briefing` record from DashboardViewModel.
struct DailyBriefingCard: View {
    let record: Record?

    private var data: DailyBriefingData? {
        record?.decodeData(as: DailyBriefingData.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            header
            if let data {
                if let headline = data.headline, !headline.isEmpty {
                    Text(headline)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let highlights = data.highlights, !highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(highlights) { h in
                            HighlightRow(highlight: h)
                        }
                    }
                }

                if let actions = data.actionItems, !actions.isEmpty {
                    Divider().padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(actions) { a in
                            ActionRow(item: a)
                        }
                    }
                }
            } else {
                Text("BioChecha hasn't reported in yet today.")
                    .font(PerchTheme.Font.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PerchTheme.Spacing.medium)
        .cardStyle()
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let rating = data?.recoveryRating {
                Circle()
                    .fill(color(for: rating))
                    .frame(width: 10, height: 10)
            }
            Text(data?.date ?? today())
                .font(PerchTheme.Font.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("BioChecha")
                .font(PerchTheme.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for rating: DailyBriefingData.RecoveryRating) -> Color {
        switch rating {
        case .green:  return .green
        case .yellow: return .orange
        case .red:    return .red
        }
    }

    private func today() -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        return df.string(from: .now)
    }
}

private struct HighlightRow: View {
    let highlight: DailyBriefingData.Highlight

    var body: some View {
        HStack(spacing: 8) {
            if let icon = highlight.icon, !icon.isEmpty {
                Text(icon)
            }
            Text(highlight.label)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)
            Spacer()
            if let detail = highlight.detail, !detail.isEmpty {
                Text(detail)
                    .font(PerchTheme.Font.captionMono)
                    .foregroundStyle(.secondary)
            }
            if let trend = highlight.trend {
                Image(systemName: trendIcon(trend))
                    .font(PerchTheme.Font.caption)
                    .foregroundStyle(trendColor(trend))
            }
        }
    }

    private func trendIcon(_ t: DailyBriefingData.Highlight.Trend) -> String {
        switch t {
        case .up:     return "arrow.up"
        case .down:   return "arrow.down"
        case .steady: return "arrow.right"
        }
    }

    private func trendColor(_ t: DailyBriefingData.Highlight.Trend) -> Color {
        switch t {
        case .up:     return .green
        case .down:   return .red
        case .steady: return .secondary
        }
    }
}

private struct ActionRow: View {
    let item: DailyBriefingData.ActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(priorityColor)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(item.text)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high:    return .red
        case .medium:  return .orange
        case .low:     return .secondary
        case .none:    return .secondary
        }
    }
}

#if DEBUG
#Preview {
    // Preview placeholder — real card renders from a DashboardViewModel record.
    DailyBriefingCard(record: nil)
        .padding()
        .background(PerchTheme.background)
}
#endif
