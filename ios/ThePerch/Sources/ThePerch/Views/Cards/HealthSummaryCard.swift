import SwiftUI

/// A composite "targets met" card showing circular indicators for each health target.
/// Displayed at the top of the Health section.
struct HealthSummaryCard: View {
    let records: [Record]

    /// Resolves the effective date for a measurement record.
    private func effectiveDate(for record: Record, measurement: MeasurementData) -> Date {
        if let ts = measurement.timestamp { return ts }
        if let ctx = measurement.context,
           let parsed = PerchFormatters.isoDate.date(from: ctx) {
            return parsed
        }
        return record.createdAt
    }

    var body: some View {
        let targets = computeTargets()
        let metCount = targets.filter { $0.status == .met }.count
        let totalWithData = targets.filter { $0.status != .noData }.count

        VStack(spacing: PerchTheme.Spacing.medium) {
            // Horizontal row of circular indicators
            HStack(spacing: PerchTheme.Spacing.medium) {
                ForEach(targets, id: \.label) { target in
                    targetIndicator(target)
                }
            }

            // Summary text
            VStack(spacing: PerchTheme.Spacing.xxSmall) {
                if totalWithData > 0 {
                    Text("\(metCount) of \(totalWithData) targets met today")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)

                    Text(summaryLabel(met: metCount, total: totalWithData))
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(summaryColor(met: metCount, total: totalWithData))
                } else {
                    Text("No target data available")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    // MARK: - Target Indicator

    private func targetIndicator(_ target: TargetInfo) -> some View {
        VStack(spacing: PerchTheme.Spacing.xxSmall) {
            ZStack {
                Circle()
                    .fill(target.status.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Circle()
                    .stroke(target.status.color.opacity(0.3), lineWidth: 2)
                    .frame(width: 40, height: 40)
                Text(target.status.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(target.status.color)
            }

            Text(target.label)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Target Computation

    private struct TargetInfo {
        let label: String
        let status: TargetStatus
    }

    private enum TargetStatus {
        case met
        case notMet
        case stable
        case noData

        var symbol: String {
            switch self {
            case .met: return "\u{2713}"
            case .notMet: return "\u{2717}"
            case .stable: return "\u{2192}"
            case .noData: return "?"
            }
        }

        var color: Color {
            switch self {
            case .met: return PerchTheme.success
            case .notMet: return PerchTheme.warning
            case .stable: return PerchTheme.accent
            case .noData: return PerchTheme.textTertiary
            }
        }
    }

    private func computeTargets() -> [TargetInfo] {
        let measurements = records.compactMap { record -> (Record, MeasurementData)? in
            guard let m = record.asMeasurement() else { return nil }
            return (record, m)
        }

        return [
            sleepTarget(measurements),
            deepSleepTarget(measurements),
            caloriesTarget(measurements),
            proteinTarget(),
            weightTarget(measurements),
        ]
    }

    private func latestMeasurement(_ measurements: [(Record, MeasurementData)], metric: String) -> MeasurementData? {
        measurements
            .filter { $0.1.metric == metric }
            .sorted { effectiveDate(for: $0.0, measurement: $0.1) > effectiveDate(for: $1.0, measurement: $1.1) }
            .first?.1
    }

    private func sleepTarget(_ measurements: [(Record, MeasurementData)]) -> TargetInfo {
        guard let m = latestMeasurement(measurements, metric: "sleep_duration") else {
            return TargetInfo(label: "Sleep", status: .noData)
        }
        return TargetInfo(label: "Sleep", status: m.value >= 7.0 ? .met : .notMet)
    }

    private func deepSleepTarget(_ measurements: [(Record, MeasurementData)]) -> TargetInfo {
        guard let m = latestMeasurement(measurements, metric: "deep_sleep") else {
            return TargetInfo(label: "Deep", status: .noData)
        }
        return TargetInfo(label: "Deep", status: m.value >= 1.0 ? .met : .notMet)
    }

    private func caloriesTarget(_ measurements: [(Record, MeasurementData)]) -> TargetInfo {
        guard let m = latestMeasurement(measurements, metric: "daily_calories"),
              let target = m.target, target > 0 else {
            return TargetInfo(label: "Cals", status: .noData)
        }
        let ratio = m.value / target
        return TargetInfo(label: "Cals", status: (ratio >= 0.9 && ratio <= 1.1) ? .met : .notMet)
    }

    private func proteinTarget() -> TargetInfo {
        let macrosRecords = records.compactMap { $0.asMacros() }
            .sorted { ($0.date ?? "") > ($1.date ?? "") }
        guard let latest = macrosRecords.first else {
            return TargetInfo(label: "Protein", status: .noData)
        }
        guard let target = latest.proteinTarget, target > 0 else {
            return TargetInfo(label: "Protein", status: .noData)
        }
        return TargetInfo(label: "Protein", status: latest.protein >= target ? .met : .notMet)
    }

    private func weightTarget(_ measurements: [(Record, MeasurementData)]) -> TargetInfo {
        let weightEntries = measurements
            .filter { $0.1.metric == "weight" }
            .sorted { effectiveDate(for: $0.0, measurement: $0.1) < effectiveDate(for: $1.0, measurement: $1.1) }
            .suffix(7)

        guard weightEntries.count >= 2 else {
            return TargetInfo(label: "Weight", status: .noData)
        }

        let values = weightEntries.map { $0.1.value }
        guard let first = values.first, let last = values.last else {
            return TargetInfo(label: "Weight", status: .noData)
        }

        let diff = last - first
        if abs(diff) < 0.3 {
            return TargetInfo(label: "Weight", status: .stable)
        }
        // Trending down is generally desired for weight management
        return TargetInfo(label: "Weight", status: diff < 0 ? .met : .notMet)
    }

    // MARK: - Summary Helpers

    private func summaryLabel(met: Int, total: Int) -> String {
        let ratio = Double(met) / Double(total)
        if ratio >= 0.8 { return "Great day" }
        if ratio >= 0.4 { return "Good progress" }
        return "Needs attention"
    }

    private func summaryColor(met: Int, total: Int) -> Color {
        let ratio = Double(met) / Double(total)
        if ratio >= 0.8 { return PerchTheme.success }
        if ratio >= 0.4 { return PerchTheme.accent }
        return PerchTheme.warning
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        HealthSummaryCard(records: [])
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
