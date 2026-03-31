import SwiftUI
import Charts

struct ChartCard: View {
    let title: String
    let records: [Record]
    let unit: String
    var formatAsTime: Bool = false
    var higherIsBetter: Bool = false

    @State private var isExpanded: Bool = false
    @State private var selectedRange: TimeRange?
    @State private var selectedDataPoint: (date: Date, value: Double)?
    @State private var lastSnappedIndex: Int?

    private let hapticGenerator = UISelectionFeedbackGenerator()

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

    private struct ChartDataPoint: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private func effectiveDate(for record: Record) -> Date {
        if let ts = record.asMeasurement()?.timestamp { return ts }
        if let ctx = record.asMeasurement()?.context, let d = PerchFormatters.isoDate.date(from: ctx) { return d }
        return record.createdAt
    }

    private var allChartData: [ChartDataPoint] {
        let mRecords = records.compactMap { r -> (Record, MeasurementData)? in
            guard let m = r.asMeasurement() else { return nil }
            return (r, m)
        }
        return mRecords.map { r, m in
            ChartDataPoint(date: effectiveDate(for: r), value: m.value)
        }
        .sorted { $0.date < $1.date }
    }

    private var filteredData: [ChartDataPoint] {
        let cutoff = Date.now.addingTimeInterval(-Double(resolvedRange.days) * 86400)
        return allChartData.filter { $0.date >= cutoff }
    }

    private var thirtyDayData: [ChartDataPoint] {
        let cutoff = Date.now.addingTimeInterval(-Double(30) * 86400)
        return allChartData.filter { $0.date >= cutoff }
    }

    private var latestValue: String {
        guard let latest = allChartData.last else { return "--" }
        return PerchFormatters.decimal.string(from: NSNumber(value: latest.value)) ?? "--"
    }

    private var trendDelta: Double? {
        let sorted = allChartData
        guard sorted.count >= 2 else { return nil }
        let current = sorted.last!.value
        let cutoff = Date.now.addingTimeInterval(-Double(resolvedRange.days) * 86400)
        let relevant = sorted.filter { $0.date >= cutoff }
        guard let first = relevant.first else { return nil }
        return current - first.value
    }

    static func trendBadgeText(current: Double, baseline: Double, unit: String, formatAsTime: Bool) -> String {
        let delta = abs(current - baseline)

        if formatAsTime {
            let minutes = Int((delta * 60).rounded())
            return "\(minutes)m"
        }

        if unit == "%" {
            return String(format: "%.1f pts", delta)
        }

        if let formatted = PerchFormatters.decimal.string(from: NSNumber(value: delta)) {
            return formatted + (unit.isEmpty ? "" : " \(unit)")
        }

        return String(format: "%.1f", delta) + (unit.isEmpty ? "" : " \(unit)")
    }

    private var trendView: some View {
        Group {
            if let trend = trendDelta,
               let first = allChartData.filter({ $0.date >= Date.now.addingTimeInterval(-Double(resolvedRange.days) * 86400) }).first,
               let latest = allChartData.last {
                let isStable = abs(trend) < 0.05
                let trendColor: Color = {
                    if isStable { return PerchTheme.textTertiary }
                    if title.caseInsensitiveCompare("Weight") == .orderedSame {
                        return PerchTheme.warning
                    }
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
                        .font(PerchTheme.Font.micro)
                        .fontWeight(.bold)
                    Text(Self.trendBadgeText(current: latest.value, baseline: first.value, unit: unit, formatAsTime: formatAsTime))
                        .font(PerchTheme.Font.captionNumeric)
                }
                .foregroundColor(trendColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(trendColor.opacity(0.1))
                .cornerRadius(4)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    static func timeValueView(_ value: Double) -> some View {
        let totalMinutes = Int(value * 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(hours)")
                .font(PerchTheme.Font.displayNumeric)
                .foregroundColor(PerchTheme.textPrimary)
            Text("h")
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textSecondary)
                .padding(.trailing, 2)
            Text("\(minutes)")
                .font(PerchTheme.Font.displayNumeric)
                .foregroundColor(PerchTheme.textPrimary)
            Text("m")
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textSecondary)
        }
    }

    static func formatHoursAsTime(_ value: Double) -> String {
        let totalMinutes = Int(value * 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isExpanded {
                collapsedView
            } else {
                expandedView
            }
        }
        .background(PerchTheme.cardBackground)
        .cornerRadius(PerchTheme.Card.cornerRadius)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
            if isExpanded {
                hapticGenerator.prepare()
            }
        }
    }

    // MARK: - Collapsed State (Sparkline)
    
    private var collapsedView: some View {
        HStack(spacing: PerchTheme.Spacing.medium) {
            // Left: Value & Title
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: PerchTheme.Spacing.small) {
                    Text(title)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)
                    trendView
                }
                
                if formatAsTime, let latest = allChartData.last?.value {
                    Self.timeValueView(latest)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(latestValue)
                            .font(PerchTheme.Font.titleNumeric)
                            .foregroundColor(PerchTheme.textPrimary)
                        Text(unit)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }
            }
            
            Spacer()
            
            // Right: Sparkline
            if !thirtyDayData.isEmpty {
                let yMin = thirtyDayData.map(\.value).min() ?? 0
                let yMax = thirtyDayData.map(\.value).max() ?? 100
                let yPadding = (yMax - yMin) * 0.2
                
                Chart {
                    ForEach(thirtyDayData) { dp in
                        LineMark(
                            x: .value("Date", dp.date),
                            y: .value("Value", dp.value)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(PerchTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: (yMin - yPadding)...(yMax + yPadding))
                .frame(width: 80, height: 40)
            }
        }
        .padding(PerchTheme.Spacing.medium)
    }

    // MARK: - Expanded State (Full Chart)
    
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Header Row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: PerchTheme.Spacing.small) {
                        Text(title)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                        trendView
                    }
                    
                    if let point = selectedDataPoint {
                        if formatAsTime {
                            Self.timeValueView(point.value)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(PerchFormatters.decimal.string(from: NSNumber(value: point.value)) ?? "--")
                                    .font(PerchTheme.Font.titleNumeric)
                                    .foregroundColor(PerchTheme.textPrimary)
                                Text(unit)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textSecondary)
                            }
                        }
                    } else {
                        if formatAsTime, let latest = allChartData.last?.value {
                            Self.timeValueView(latest)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(latestValue)
                                    .font(PerchTheme.Font.titleNumeric)
                                    .foregroundColor(PerchTheme.textPrimary)
                                Text(unit)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textSecondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Timeframe Picker (moved to top right)
                HStack(spacing: 8) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue)
                            .font(PerchTheme.Font.micro)
                            .foregroundColor(resolvedRange == range ? PerchTheme.accentForeground : PerchTheme.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(resolvedRange == range ? PerchTheme.accent : Color.clear)
                            .cornerRadius(12)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedRange = range
                                }
                            }
                    }
                }
                .padding(4)
                .background(PerchTheme.cardInnerBackground)
                .cornerRadius(16)
            }
            
            // Full Chart
            let data = filteredData
            if data.isEmpty {
                Text("Not enough data for this period")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
            } else {
                let yMin = data.map(\.value).min() ?? 0
                let yMax = data.map(\.value).max() ?? 100
                let yPadding = (yMax - yMin) * 0.1
                let hasEnoughPointsForLine = data.count > 2

                Chart {
                    ForEach(data) { dp in
                        if hasEnoughPointsForLine {
                            LineMark(
                                x: .value("Date", dp.date),
                                y: .value("Value", dp.value)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(PerchTheme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            
                            PointMark(
                                x: .value("Date", dp.date),
                                y: .value("Value", dp.value)
                            )
                            .foregroundStyle(PerchTheme.accent)
                            .symbolSize(12)
                        } else {
                            PointMark(
                                x: .value("Date", dp.date),
                                y: .value("Value", dp.value)
                            )
                            .foregroundStyle(PerchTheme.accent)
                            .symbolSize(30)
                        }
                    }
                    
                    if let point = selectedDataPoint {
                        RuleMark(x: .value("Date", point.date))
                            .foregroundStyle(PerchTheme.textTertiary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                            .annotation(position: .top) {
                                Text(PerchFormatters.shortDate.string(from: point.date))
                                    .font(PerchTheme.Font.micro)
                                    .foregroundColor(PerchTheme.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PerchTheme.cardInnerBackground)
                                    .cornerRadius(4)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .stride(by: .day, count: resolvedRange == .sevenDays ? 1 : (resolvedRange == .thirtyDays ? 7 : 14))) { value in
                        if let date = value.as(Date.self) {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(PerchTheme.border)
                            AxisValueLabel {
                                Text(PerchFormatters.shortDate.string(from: date))
                                    .font(PerchTheme.Font.micro)
                                    .foregroundColor(PerchTheme.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(PerchTheme.border)
                        AxisValueLabel {
                            if let intVal = value.as(Double.self) {
                                Text(formatAsTime ? "\(Int(intVal))h" : "\(Int(intVal))")
                                    .font(PerchTheme.Font.microNumeric)
                                    .foregroundColor(PerchTheme.textTertiary)
                            }
                        }
                    }
                }
                .chartYScale(domain: (yMin - yPadding)...(yMax + yPadding))
                .frame(height: 140)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let x = value.location.x - geo[proxy.plotFrame!].origin.x
                                        guard let date: Date = proxy.value(atX: x) else { return }
                                        
                                        // Snap to closest point
                                        if let closestIndex = data.enumerated()
                                            .min(by: { abs($0.element.date.timeIntervalSince(date)) < abs($1.element.date.timeIntervalSince(date)) })?.offset {
                                            
                                            let point = data[closestIndex]
                                            selectedDataPoint = (date: point.date, value: point.value)
                                            
                                            if lastSnappedIndex != closestIndex {
                                                hapticGenerator.selectionChanged()
                                                lastSnappedIndex = closestIndex
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        selectedDataPoint = nil
                                        lastSnappedIndex = nil
                                    }
                            )
                    }
                }
            }
        }
        .padding(PerchTheme.Spacing.medium)
    }
}
