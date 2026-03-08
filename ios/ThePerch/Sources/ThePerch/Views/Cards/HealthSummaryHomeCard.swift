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
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: isCompact ? "chevron.down" : "chevron.up")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                // Four metric circles
                HStack(spacing: PerchTheme.Spacing.small) {
                    if let sleep = sleepDuration {
                        metricCircle(
                            value: formatHours(sleep.value),
                            label: "sleep",
                            color: sleep.value >= 7 ? PerchTheme.success : (sleep.value >= 6 ? PerchTheme.warning : PerchTheme.error)
                        )
                    }
                    if let deep = deepSleep {
                        metricCircle(
                            value: formatHours(deep.value),
                            label: "deep",
                            color: deep.value >= 1 ? PerchTheme.success : (deep.value >= 0.5 ? PerchTheme.warning : PerchTheme.error)
                        )
                    }
                    if let h = hrv {
                        metricCircle(
                            value: "\(Int(h.value))",
                            label: "HRV",
                            color: PerchTheme.textPrimary
                        )
                    }
                    if let r = readiness {
                        metricCircle(
                            value: "\(Int(r.value))",
                            label: "ready",
                            color: r.value >= 85 ? PerchTheme.success : (r.value >= 70 ? PerchTheme.warning : PerchTheme.error)
                        )
                    }
                }

                // Sleep score bar (expanded mode only)
                if let score = sleepScore {
                    sleepScoreBar(score: score.value)
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .animation(.easeInOut(duration: 0.3), value: isCompact)
    }

    // MARK: - Components

    private func metricCircle(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(PerchTheme.border, lineWidth: 3)
                    .frame(width: 56, height: 56)
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 3)
                    .frame(width: 56, height: 56)
                VStack(spacing: 1) {
                    Text(value)
                        .font(PerchTheme.Font.headingNumeric)
                        .foregroundColor(PerchTheme.textPrimary)
                    Text(label)
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sleepScoreBar(score: Double) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
            HStack {
                Text("Sleep Score")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
                Spacer()
                Text("\(Int(score))")
                    .font(PerchTheme.Font.headingNumeric)
                    .foregroundColor(PerchTheme.textPrimary)
                Text(scoreLabel(score))
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(scoreColor(score))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PerchTheme.cardInnerBackground)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(scoreColor(score))
                        .frame(width: geometry.size.width * min(score / 100, 1.0), height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Helpers

    private func formatHours(_ value: Double) -> String {
        let hours = Int(value)
        let minutes = Int((value - Double(hours)) * 60)
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h\(minutes)"
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
