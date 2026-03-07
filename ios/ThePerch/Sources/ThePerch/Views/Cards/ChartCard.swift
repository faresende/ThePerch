import SwiftUI
import Charts

/// Displays measurement data as a line chart with gradient fill.
/// Darker theme with amber line and warm glow.
struct ChartCard: View {
    let title: String
    let records: [Record]
    let unit: String
    var formatAsTime: Bool = false
    /// When true, an upward trend shows green (good). When false, upward = red (bad).
    var higherIsBetter: Bool = false

    @State private var selectedRange: TimeRange?

    /// Auto-selects the best time range on first appearance.
    /// Picks the smallest range that contains at least 2 data points for a proper chart.
    private var resolvedRange: TimeRange {
        selectedRange ?? bestInitialRange
    }

    private var bestInitialRange: TimeRange {
        for range in TimeRange.allCases {
            let cutoff = Date.now.addingTimeInterval(-Double(range.days) * 86400)
            let count = records.filter { effectiveDate(for: $0) >= cutoff }.count
            if count >= 2 { return range }
        }
        return .ninetyDays
    }

    enum TimeRange: String, CaseIterable {
        case sevenDays = "7d"
        case thirtyDays = "30d"
        case ninetyDays = "90d"

        var days: Int {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            }
        }
    }

    /// Returns the effective date for a record — uses the measurement's timestamp if available,
    /// otherwise falls back to the record's createdAt. This is critical because Claudinho
    /// often bulk-inserts records with the same `created_at` but different data timestamps.
    private func effectiveDate(for record: Record) -> Date {
        if let m = record.asMeasurement(), let ts = m.timestamp {
            return ts
        }
        return record.createdAt
    }

    var filteredRecords: [Record] {
        let cutoff = Date.now.addingTimeInterval(-Double(resolvedRange.days) * 86400)
        return records.filter { effectiveDate(for: $0) >= cutoff }
            .sorted { effectiveDate(for: $0) < effectiveDate(for: $1) }
    }

    var chartData: [(date: Date, value: Double)] {
        filteredRecords.compactMap { record in
            guard let m = record.asMeasurement() else { return nil }
            return (date: effectiveDate(for: record), value: m.value)
        }
    }

    /// All data points sorted by effective date, regardless of selected time range.
    /// Used for the header to always show the most recent reading.
    private var allChartData: [(date: Date, value: Double)] {
        records.compactMap { record in
            guard let m = record.asMeasurement() else { return nil }
            return (date: effectiveDate(for: record), value: m.value)
        }.sorted { $0.date < $1.date }
    }

    var latestValue: String {
        guard let latest = allChartData.last?.value else { return "—" }
        if formatAsTime {
            return Self.formatHoursAsTime(latest)
        }
        return String(format: "%.1f", latest)
    }

    /// Converts decimal hours to "Xh Ym" format (e.g. 0.38 → "0h 23m", 6.45 → "6h 27m").
    static func formatHoursAsTime(_ hours: Double) -> String {
        let totalMinutes = Int(round(hours * 60))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h)h \(m)m"
    }

    /// Rich text view for time values with smaller h/m labels.
    @ViewBuilder
    static func timeValueView(_ hours: Double) -> some View {
        let totalMinutes = Int(round(hours * 60))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(h)")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(PerchTheme.textPrimary)
            Text("h")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(PerchTheme.textSecondary)
            Text("\(m)")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(PerchTheme.textPrimary)
            Text("m")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(PerchTheme.textSecondary)
        }
    }

    var trendPercent: Double? {
        guard chartData.count >= 2 else { return nil }
        let first = chartData.first!.value
        let last = chartData.last!.value
        guard first > 0 else { return nil }
        return ((last - first) / first) * 100
    }

    var yRange: ClosedRange<Double> {
        let values = chartData.map { $0.value }
        guard let lo = values.min(), let hi = values.max() else { return 0...100 }
        let range = hi - lo
        let padding = max(range * 0.4, 0.5)
        return (lo - padding)...(hi + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PerchTheme.textSecondary)

                    if formatAsTime, let latest = allChartData.last?.value {
                        Self.timeValueView(latest)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(latestValue)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(PerchTheme.textPrimary)

                            Text(unit)
                                .font(.system(size: 14))
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                    }
                }

                Spacer()

                if let trend = trendPercent {
                    let isStable = abs(trend) < 0.5
                    let trendColor: Color = {
                        if isStable { return PerchTheme.textTertiary }
                        let isPositive = trend > 0
                        if higherIsBetter {
                            return isPositive ? PerchTheme.success : PerchTheme.error
                        } else {
                            return isPositive ? PerchTheme.error : PerchTheme.success
                        }
                    }()
                    let icon: String = {
                        if isStable { return "arrow.right" }
                        return trend > 0 ? "arrow.up.right" : "arrow.down.right"
                    }()

                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(String(format: "%.1f%%", abs(trend)))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(trendColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(trendColor.opacity(0.15))
                    .cornerRadius(8)
                }
            }

            // Chart
            if chartData.count >= 2 {
                Chart(chartData, id: \.date) { item in
                    AreaMark(
                        x: .value("Date", item.date),
                        yStart: .value("Min", yRange.lowerBound),
                        yEnd: .value("Value", item.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                PerchTheme.accent.opacity(0.25),
                                PerchTheme.accent.opacity(0.05),
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(PerchTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", item.date),
                        y: .value("Value", item.value)
                    )
                    .foregroundStyle(PerchTheme.accent)
                    .symbolSize(24)
                }
                .chartYScale(domain: yRange)
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .chartPlotStyle { plot in
                    plot.background(Color.clear)
                }
                .frame(height: 110)
            } else {
                // Single or no data
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Circle()
                            .fill(PerchTheme.accent)
                            .frame(width: 8, height: 8)
                            .shadow(color: PerchTheme.accent.opacity(0.4), radius: 4)
                        Text(chartData.isEmpty ? "No data yet" : "Single reading")
                            .font(.system(size: 12))
                            .foregroundColor(PerchTheme.textTertiary)
                    }
                    Spacer()
                }
                .frame(height: 50)
            }

            // Time range selector
            HStack(spacing: 4) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Button(action: { selectedRange = range }) {
                        Text(range.rawValue)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(
                                resolvedRange == range
                                    ? .black
                                    : PerchTheme.textSecondary
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                resolvedRange == range
                                    ? PerchTheme.accent
                                    : PerchTheme.cardInnerBackground
                            )
                            .cornerRadius(10)
                    }
                }
            }
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
    }
}

// MARK: - Preview

#Preview {
    ChartCard(
        title: "Weight",
        records: MockData.measurementRecords,
        unit: "kg"
    )
    .padding(PerchTheme.Spacing.large)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
