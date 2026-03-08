import SwiftUI
import Charts

/// Full-screen detail view for a health metric chart.
/// Shows an expanded chart with trend analysis, goal line, time range selector, and streak.
struct HealthDetailView: View {
    let title: String
    let records: [Record]
    let unit: String
    var formatAsTime: Bool = false
    var higherIsBetter: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRange: TimeRange = .thirtyDays

    // MARK: - Time Range

    enum TimeRange: String, CaseIterable {
        case sevenDays = "7D"
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        case all = "All"

        var days: Int? {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .all: return nil
            }
        }
    }

    // MARK: - Goal Targets

    private static let goalTargets: [String: Double] = [
        "sleep_duration": 7.0,
        "deep_sleep": 1.0,
        "avg_sleep_hrv": 50.0,
    ]

    private var goalValue: Double? {
        let metricKey = title.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "%", with: "pct")
        return Self.goalTargets[metricKey]
    }

    // MARK: - Chart Data

    private var allChartData: [(date: Date, value: Double)] {
        records.compactMap { record in
            guard let m = record.asMeasurement() else { return nil }
            let date = m.timestamp ?? record.createdAt
            return (date: date, value: m.value)
        }.sorted { $0.date < $1.date }
    }

    private var chartData: [(date: Date, value: Double)] {
        guard let days = selectedRange.days else { return allChartData }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return allChartData.filter { $0.date >= cutoff }
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
        var values = chartData.map { $0.value }
        if let goal = goalValue { values.append(goal) }
        guard let lo = values.min(), let hi = values.max() else { return 0...100 }
        let range = hi - lo
        let padding = max(range * 0.3, 0.5)
        return (lo - padding)...(hi + padding)
    }

    // MARK: - Trend Analysis

    private var trendInfo: (percentage: Double, isImproving: Bool, label: String)? {
        let data = allChartData
        guard data.count >= 2 else { return nil }

        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!

        let lastWeek = data.filter { $0.date >= sevenDaysAgo }
        let prevWeek = data.filter { $0.date >= fourteenDaysAgo && $0.date < sevenDaysAgo }

        guard !lastWeek.isEmpty, !prevWeek.isEmpty else { return nil }

        let lastAvg = lastWeek.map(\.value).reduce(0, +) / Double(lastWeek.count)
        let prevAvg = prevWeek.map(\.value).reduce(0, +) / Double(prevWeek.count)

        guard prevAvg != 0 else { return nil }

        let pctChange = ((lastAvg - prevAvg) / prevAvg) * 100
        let isUp = pctChange > 0
        let isImproving = higherIsBetter ? isUp : !isUp
        let arrow = isUp ? "↑" : "↓"
        let label = "\(arrow) \(String(format: "%.1f", abs(pctChange)))% vs prev week"

        return (percentage: pctChange, isImproving: isImproving, label: label)
    }

    private var trendColor: Color {
        guard let trend = trendInfo else { return PerchTheme.textSecondary }
        if abs(trend.percentage) <= 1.0 { return .orange }
        return trend.isImproving ? PerchTheme.success : PerchTheme.error
    }

    // MARK: - Streak

    private var streakDays: Int {
        guard let goal = goalValue else { return 0 }
        let data = allChartData

        // Group by day, take latest value per day
        var dailyValues: [String: Double] = [:]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for point in data {
            let key = fmt.string(from: point.date)
            dailyValues[key] = point.value
        }

        // Count consecutive days (from today backwards) meeting goal
        var streak = 0
        var date = Date()
        for _ in 0..<365 {
            let key = fmt.string(from: date)
            guard let value = dailyValues[key] else { break }
            if value >= goal {
                streak += 1
            } else {
                break
            }
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return streak
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                PerchTheme.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                        // Latest value + trend
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

                                HStack(spacing: PerchTheme.Spacing.small) {
                                    Text("Latest reading")
                                        .font(PerchTheme.Font.caption)
                                        .foregroundColor(PerchTheme.textTertiary)

                                    if let trend = trendInfo {
                                        Text(trend.label)
                                            .font(PerchTheme.Font.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(trendColor)
                                    }
                                }
                            }
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }

                        // Time range selector
                        Picker("Time Range", selection: $selectedRange) {
                            ForEach(TimeRange.allCases, id: \.self) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, PerchTheme.Spacing.large)

                        // Full chart with optional goal line
                        if chartData.count >= 2 {
                            Chart {
                                ForEach(chartData, id: \.date) { item in
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

                                // Goal line
                                if let goal = goalValue {
                                    RuleMark(y: .value("Goal", goal))
                                        .foregroundStyle(PerchTheme.success.opacity(0.7))
                                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                        .annotation(position: .top, alignment: .trailing) {
                                            Text("Goal: \(formatValue(goal))")
                                                .font(PerchTheme.Font.micro)
                                                .foregroundColor(PerchTheme.success)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(PerchTheme.success.opacity(0.1))
                                                .cornerRadius(4)
                                        }
                                }
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

                        // Streak indicator
                        if goalValue != nil && streakDays > 0 {
                            HStack(spacing: PerchTheme.Spacing.xSmall) {
                                Text("\u{1F525} \(streakDays) day streak")
                                    .font(PerchTheme.Font.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(PerchTheme.accent)
                            }
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
