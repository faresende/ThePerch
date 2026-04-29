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
    /// Legacy parameter retained so call sites that pass `compact:`
    /// keep compiling. Ignored — the card always renders expanded
    /// now (graph + metrics + phrase). The previous tap-to-collapse
    /// behaviour was confusing: the card landed collapsed by default,
    /// hiding the sleep graph behind an unmarked tap target.
    var compact: Bool = false

    @Environment(\.perchPalette) private var palette

    /// Round 9 perf: single-pass snapshot of the 5 measurements + latestUpdate.
    /// Replaces 9 redundant filter+sort passes per body render. Recomputed
    /// only when `records` materially changes (count + max(updatedAt)).
    @State private var snapshot: Snapshot = .empty

    private struct Snapshot {
        var sleepDuration: MeasurementData?
        var deepSleep: MeasurementData?
        var hrv: MeasurementData?
        var readiness: MeasurementData?
        var sleepScore: MeasurementData?
        var latestUpdate: Date?
        var hasData: Bool

        static let empty = Snapshot(
            sleepDuration: nil, deepSleep: nil, hrv: nil,
            readiness: nil, sleepScore: nil,
            latestUpdate: nil, hasData: false
        )

        /// Single pass over records: filter health-measurements, track
        /// latest-by-metric and the global max(updatedAt). Tuple
        /// equality on MeasurementData is `Equatable`-driven (struct).
        static func compute(from records: [Record]) -> Snapshot {
            var latestByMetric: [String: (MeasurementData, Date)] = [:]
            var latestUpdate: Date?
            for r in records where r.category == .health && r.type == .measurement {
                if let cur = latestUpdate {
                    if r.updatedAt > cur { latestUpdate = r.updatedAt }
                } else {
                    latestUpdate = r.updatedAt
                }
                guard let m = r.asMeasurement() else { continue }
                let ts = m.timestamp ?? .distantPast
                if let existing = latestByMetric[m.metric], existing.1 >= ts { continue }
                latestByMetric[m.metric] = (m, ts)
            }
            return Snapshot(
                sleepDuration: latestByMetric["sleep_duration"]?.0,
                deepSleep:     latestByMetric["deep_sleep"]?.0,
                hrv:           latestByMetric["avg_sleep_hrv"]?.0,
                readiness:     latestByMetric["readiness_score"]?.0,
                sleepScore:    latestByMetric["sleep_score"]?.0,
                latestUpdate:  latestUpdate,
                hasData:       latestByMetric["sleep_duration"] != nil
            )
        }
    }

    /// Cheap fingerprint — count of health measurements + max(updatedAt)
    /// in the source array. Hashable so it can drive `.onChange(of:)`
    /// without per-render String allocation.
    private struct Fingerprint: Hashable {
        let count: Int
        let maxUpdated: TimeInterval

        static func from(_ records: [Record]) -> Fingerprint {
            var count = 0
            var maxUpd: TimeInterval = 0
            for r in records where r.category == .health && r.type == .measurement {
                count += 1
                let t = r.updatedAt.timeIntervalSince1970
                if t > maxUpd { maxUpd = t }
            }
            return Fingerprint(count: count, maxUpdated: maxUpd)
        }
    }

    /// Convenience accessors so the rest of the body reads unchanged.
    private var sleepDuration: MeasurementData? { snapshot.sleepDuration }
    private var deepSleep:     MeasurementData? { snapshot.deepSleep }
    private var hrv:           MeasurementData? { snapshot.hrv }
    private var readiness:     MeasurementData? { snapshot.readiness }
    private var sleepScore:    MeasurementData? { snapshot.sleepScore }
    private var hasData:       Bool             { snapshot.hasData }
    private var latestUpdate:  Date?            { snapshot.latestUpdate }

    var body: some View {
        TodayCard {
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
        }
        .onAppear {
            snapshot = Snapshot.compute(from: records)
        }
        .onChange(of: Fingerprint.from(records)) { _, _ in
            snapshot = Snapshot.compute(from: records)
        }
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
        Self.weekdayLetterFormatter.string(from: date)
    }

    /// Phase 3 perf: cached. Sleep graph renders 7 bars × per render
    /// of the Health card. Was creating 7 DateFormatters per render.
    /// Reuses PerchFormatters.dayLetter format spec.
    private static let weekdayLetterFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateFormat = "EEEEE"  // single-letter weekday (M, T, W…)
        return f
    }()

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
