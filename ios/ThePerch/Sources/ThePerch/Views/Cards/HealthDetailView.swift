import SwiftUI
import Charts

/// Full-screen detail view for a health metric chart.
/// Shows an expanded chart with all data points and statistics.
struct HealthDetailView: View {
    let title: String
    let records: [Record]
    let unit: String
    var formatAsTime: Bool = false
    var higherIsBetter: Bool = false

    @Environment(\.dismiss) private var dismiss

    private var chartData: [(date: Date, value: Double)] {
        records.compactMap { record in
            guard let m = record.asMeasurement() else { return nil }
            let date = m.timestamp ?? record.createdAt
            return (date: date, value: m.value)
        }.sorted { $0.date < $1.date }
    }

    private var stats: (min: Double, max: Double, avg: Double, count: Int)? {
        let values = chartData.map { $0.value }
        guard !values.isEmpty else { return nil }
        let min = values.min()!
        let max = values.max()!
        let avg = values.reduce(0, +) / Double(values.count)
        return (min: min, max: max, avg: avg, count: values.count)
    }

    private var yRange: ClosedRange<Double> {
        let values = chartData.map { $0.value }
        guard let lo = values.min(), let hi = values.max() else { return 0...100 }
        let range = hi - lo
        let padding = max(range * 0.3, 0.5)
        return (lo - padding)...(hi + padding)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PerchTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                        // Latest value
                        if let latest = chartData.last {
                            VStack(alignment: .leading, spacing: 4) {
                                if formatAsTime {
                                    ChartCard.timeValueView(latest.value)
                                } else {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(String(format: "%.1f", latest.value))
                                            .font(PerchTheme.Font.displayNumeric)
                                            .foregroundColor(PerchTheme.textPrimary)
                                        Text(unit)
                                            .font(PerchTheme.Font.heading)
                                            .foregroundColor(PerchTheme.textSecondary)
                                    }
                                }
                                Text("Latest reading")
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textTertiary)
                            }
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }

                        // Full chart
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
                                            PerchTheme.accent.opacity(0.3),
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
                                .symbolSize(30)
                            }
                            .chartYScale(domain: yRange)
                            .chartXAxis {
                                AxisMarks(values: .automatic) { _ in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                        .foregroundStyle(PerchTheme.border)
                                    AxisValueLabel()
                                        .foregroundStyle(PerchTheme.textTertiary)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading) { _ in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                        .foregroundStyle(PerchTheme.border)
                                    AxisValueLabel()
                                        .foregroundStyle(PerchTheme.textTertiary)
                                }
                            }
                            .frame(height: 280)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }

                        // Stats
                        if let stats {
                            VStack(spacing: PerchTheme.Spacing.small) {
                                statRow(label: "Minimum", value: formatValue(stats.min))
                                statRow(label: "Maximum", value: formatValue(stats.max))
                                statRow(label: "Average", value: formatValue(stats.avg))
                                statRow(label: "Data points", value: "\(stats.count)")
                            }
                            .padding(PerchTheme.Card.padding)
                            .cardStyle()
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }

                        // All readings
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                            Text("All Readings")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)
                                .padding(.horizontal, PerchTheme.Spacing.large)

                            ForEach(chartData.reversed(), id: \.date) { point in
                                HStack {
                                    Text(point.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(PerchTheme.Font.caption)
                                        .foregroundColor(PerchTheme.textSecondary)
                                    Spacer()
                                    Text(formatValue(point.value))
                                        .font(PerchTheme.Font.bodyNumeric)
                                        .foregroundColor(PerchTheme.textPrimary)
                                }
                                .padding(.horizontal, PerchTheme.Spacing.large)
                                .padding(.vertical, 6)
                            }
                        }

                        Spacer().frame(height: PerchTheme.Spacing.large)
                    }
                    .padding(.top, PerchTheme.Spacing.medium)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(PerchTheme.accent)
                }
            }
            .toolbarBackground(PerchTheme.background, for: .navigationBar)
        }
    }

    private func formatValue(_ value: Double) -> String {
        if formatAsTime {
            return ChartCard.formatHoursAsTime(value)
        }
        return String(format: "%.1f", value) + " " + unit
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textSecondary)
            Spacer()
            Text(value)
                .font(PerchTheme.Font.bodyNumeric)
                .foregroundColor(PerchTheme.textPrimary)
        }
    }
}

#Preview {
    HealthDetailView(
        title: "Weight",
        records: MockData.measurementRecords,
        unit: "kg"
    )
}
