import SwiftUI

/// Modular health summary card for the Home screen.
/// Shows sleep duration, deep sleep, HRV, and readiness score as metric circles.
/// Below: sleep score bar with label.
/// Data: filters records where category == .health, type == .measurement.
struct HealthSummaryHomeCard: View {
    let records: [Record]
    /// When true, the parent forces compact mode (e.g. afternoon/evening).
    var compact: Bool = false

    @AppStorage("card_compact_health") private var userCompact = false

    /// Effective compact state: forced by time-of-day OR user toggle
    private var isCompact: Bool { compact || userCompact }

    private var healthRecords: [MeasurementData] {
        records
            .filter { $0.category == .health && $0.type == .measurement }
            .compactMap { $0.asMeasurement() }
    }

    private func latestMetric(_ name: String) -> MeasurementData? {
        healthRecords
            .filter { $0.metric == name }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .first
    }

    private var sleepDuration: MeasurementData? { latestMetric("sleep_duration") }
    private var deepSleep: MeasurementData? { latestMetric("deep_sleep") }
    private var hrv: MeasurementData? { latestMetric("avg_sleep_hrv") }
    private var readiness: MeasurementData? { latestMetric("readiness_score") }
    private var sleepScore: MeasurementData? { latestMetric("sleep_score") }

    private var hasData: Bool { sleepDuration != nil }

    private var latestUpdate: Date? {
        records
            .filter { $0.category == .health && $0.type == .measurement }
            .map(\.updatedAt)
            .max()
    }

    /// Compact summary text for single-line display
    private var compactSummary: String {
        var parts: [String] = []
        if let s = sleepDuration { parts.append("\(formatHours(s.value)) sleep") }
        if let r = readiness { parts.append("\(Int(r.value)) readiness") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Tappable header
            Button {
                PerchHaptics.selection()
                PerchMotion.withOptionalAnimation(.easeInOut(duration: 0.3)) {
                    userCompact.toggle()
                }
            } label: {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Image(systemName: "bed.double.fill")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.accent)
                    Text("SLEEP & RECOVERY")
                        .font(PerchTheme.Font.cardEyebrow)
                        .foregroundColor(PerchTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                    CardFreshnessLabel(date: latestUpdate)
                    Image(systemName: isCompact ? "chevron.down" : "chevron.up")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle())

            if !hasData {
                // Empty state
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "bed.double.fill")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.large))
                        .foregroundColor(PerchTheme.textTertiary)
                    Text("Waiting for sleep data...")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, PerchTheme.Spacing.medium)
            } else if isCompact {
                // Compact: single-line summary
                Text(compactSummary)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
            } else {
                // Hero row: score + qualifier + duration
                if let score = sleepScore {
                    HStack(alignment: .firstTextBaseline, spacing: PerchTheme.Spacing.small) {
                        Text("\(Int(score.value))")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(PerchTheme.textPrimary)

                        Text(scoreLabel(score.value))
                            .font(PerchTheme.Font.caption)
                            .fontWeight(.medium)
                            .foregroundColor(scoreColor(score.value))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(scoreColor(score.value).opacity(0.15))
                            .cornerRadius(6)

                        Spacer()

                        if let sleep = sleepDuration {
                            Text("\(formatDuration(sleep.value)) sleep")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PerchTheme.cardInnerBackground)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(scoreColor(score.value))
                                .frame(width: geo.size.width * min(score.value / 100, 1.0), height: 4)
                        }
                    }
                    .frame(height: 4)
                } else if let sleep = sleepDuration {
                    // No score available, show duration as hero
                    Text(formatDuration(sleep.value))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(PerchTheme.textPrimary)
                }

                // Secondary metrics: inline text row
                let secondaryParts = secondaryMetricsText
                if !secondaryParts.isEmpty {
                    Text(secondaryParts)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .animation(.easeInOut(duration: 0.3), value: isCompact)
    }

    // MARK: - Helpers

    private var secondaryMetricsText: String {
        var parts: [String] = []
        if let deep = deepSleep { parts.append("Deep \(formatHours(deep.value))") }
        if let h = hrv { parts.append("HRV \(Int(h.value))") }
        if let r = readiness { parts.append("Ready \(Int(r.value))") }
        return parts.joined(separator: "  ·  ")
    }

    private func formatHours(_ value: Double) -> String {
        let hours = Int(value)
        let minutes = Int((value - Double(hours)) * 60)
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h\(minutes)"
    }

    private func formatDuration(_ value: Double) -> String {
        let totalMinutes = Int(round(value * 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    private func scoreLabel(_ score: Double) -> String {
        if score >= 85 { return "Excellent" }
        if score >= 70 { return "Good" }
        if score >= 50 { return "Fair" }
        return "Poor"
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 85 { return PerchTheme.success }
        if score >= 70 { return PerchTheme.accent }
        if score >= 50 { return PerchTheme.warning }
        return PerchTheme.error
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        HealthSummaryHomeCard(records: [])
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
