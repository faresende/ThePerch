import SwiftUI

/// Modular health summary card for the Home screen.
/// Shows sleep duration, deep sleep, HRV, and readiness score as metric circles.
/// Below: sleep score bar with label.
/// Data: filters records where category == .health, type == .measurement.
struct HealthSummaryHomeCard: View {
    let records: [Record]
    /// Last 7 nights of sleep_duration_min, oldest first. Drives the
    /// sparkline. Empty when no data yet.
    var sleepHistory: [DashboardViewModel.SleepNight] = []
    /// When true, the parent forces compact mode (e.g. afternoon/evening).
    var compact: Bool = false

    @AppStorage("card_compact_health") private var userCompact = false
    @Environment(\.perchPalette) private var palette

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
        TodayCard {
            Button {
                PerchHaptics.selection()
                PerchMotion.withOptionalAnimation(.easeInOut(duration: 0.3)) {
                    userCompact.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    TodayEyebrow(
                        label: "HEALTH · OVERNIGHT",
                        accent: palette.wellness,
                        freshness: freshnessText
                    )

                    if !hasData {
                        Text("Waiting for sleep data…")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(palette.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else if isCompact {
                        Text(compactSummary)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        healthPhrase
                            .padding(.bottom, 16)
                        metricsRow
                        if !sleepHistory.isEmpty {
                            sleepGraph
                                .padding(.top, 14)
                        }
                        if let score = sleepScore {
                            Text(scoreLabel(score.value))
                                .font(.system(size: 12))
                                .foregroundColor(palette.muted)
                                .padding(.top, 12)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle())
        }
        .animation(.easeInOut(duration: 0.3), value: isCompact)
    }

    /// "5:42 am" freshness stamp derived from most recent measurement.
    private var freshnessText: String {
        guard let date = latestUpdate else { return "—" }
        let f = PerchFormatters.healthFreshness
        return f.string(from: date)
    }

    @ViewBuilder
    private var healthPhrase: some View {
        let recoveryPct = Int(readiness?.value ?? sleepScore?.value ?? 0)
        TodayPhrase(text: PerchPhrase.healthPhrase(recovery: recoveryPct))
    }

    /// Sleep duration sparkline — 7 nights, bars sized to relative
    /// duration. Colored by Editorial Linen wellness tone for "good"
    /// (>= 7h) and a muted faint for "short" (< 6h). Latest night
    /// (rightmost bar) gets a subtle ring so it's clearly the
    /// "tonight just past."
    @ViewBuilder
    private var sleepGraph: some View {
        let nights = sleepHistory
        // Normalize to a target band 5-9 hours so bars are
        // comparable across users without exaggerating the lows.
        let minMin: Double = 5 * 60
        let maxMin: Double = 9 * 60
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST 7 NIGHTS")
                .font(.system(size: 9.5))
                .tracking(0.8)
                .foregroundColor(palette.faint)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(nights.enumerated()), id: \.offset) { idx, night in
                    let clamped = max(minMin, min(maxMin, night.minutes))
                    let frac = (clamped - minMin) / max(1, maxMin - minMin)
                    let isLatest = idx == nights.count - 1
                    let isShort = night.minutes < 6 * 60
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isShort ? palette.faint : palette.wellness)
                            .frame(height: max(6, 44 * frac))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(palette.ink.opacity(isLatest ? 0.35 : 0), lineWidth: 1)
                            )
                            .frame(maxHeight: 44, alignment: .bottom)
                        Text(weekdayLetter(night.date))
                            .font(.system(size: 9, weight: isLatest ? .semibold : .regular))
                            .foregroundColor(isLatest ? palette.ink : palette.faint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60)
        }
    }

    private func weekdayLetter(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateFormat = "EEEEE"  // single-letter weekday (M, T, W…)
        return f.string(from: date)
    }

    /// Three metrics in a horizontal row: SLEEP / RECOVERY / READINESS.
    @ViewBuilder
    private var metricsRow: some View {
        HStack(spacing: 20) {
            metric(label: "SLEEP", value: sleepDuration.map { formatDuration($0.value) } ?? "—", unit: "")
            metric(label: "RECOVERY", value: readiness.map { "\(Int($0.value))" } ?? sleepScore.map { "\(Int($0.value))" } ?? "—", unit: "%")
            metric(label: "READINESS", value: readiness.map { "\(Int($0.value))" } ?? "—", unit: "%")
        }
    }

    @ViewBuilder
    private func metric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9.5))
                .tracking(0.8)
                .foregroundColor(palette.faint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(PerchTheme.Font.metricNumeric)
                    .tracking(-0.5)
                    .foregroundColor(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundColor(palette.ink.opacity(0.55))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
