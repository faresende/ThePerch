import SwiftUI

/// A synthesized daily summary card that appears at the top of HomeView.
/// Shows a morning brief (before 14:00) or evening brief (after 14:00).
struct DailyBriefCard: View {
    let records: [Record]

    private var isMorning: Bool {
        Calendar.current.component(.hour, from: .now) < 14
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Header
            HStack(spacing: PerchTheme.Spacing.xSmall) {
                Image(systemName: isMorning ? "sun.horizon.fill" : "moon.stars.fill")
                    .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                    .foregroundColor(PerchTheme.accent)
                Text(isMorning ? "Morning Brief" : "Evening Brief")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)
                Spacer()
                Text(briefDateString)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
            }

            briefDivider

            if isMorning {
                morningBrief
            } else {
                eveningBrief
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    // MARK: - Morning Brief

    @ViewBuilder
    private var morningBrief: some View {
        // Sleep summary
        if let sleep = sleepSummary {
            briefSection(icon: "bed.double.fill", title: "Sleep") {
                HStack(spacing: PerchTheme.Spacing.medium) {
                    metricPill(value: sleep.duration, label: "hours")
                    if let deep = sleep.deepSleep {
                        metricPill(value: deep, label: "deep")
                    }
                    if let hrv = sleep.hrv {
                        metricPill(value: hrv, label: "HRV", isInteger: true)
                    }
                }
            }

            briefDivider
        }

        // Today's calendar
        if let cal = calendarSummary {
            briefSection(icon: "calendar", title: "Today") {
                if cal.eventCount == 0 {
                    Text("No events scheduled")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                        Text("\(cal.eventCount) event\(cal.eventCount == 1 ? "" : "s")")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                        if let first = cal.firstEvent {
                            Text("\(first.time) — \(first.title)")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            briefDivider
        }

        // Active deliveries
        if let deliveries = deliverySummary, deliveries.total > 0 {
            briefSection(icon: "shippingbox.fill", title: "Deliveries") {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                    Text("\(deliveries.total) active")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)
                    if deliveries.outForDelivery > 0 {
                        HStack(spacing: PerchTheme.Spacing.xxSmall) {
                            Circle()
                                .fill(PerchTheme.success)
                                .frame(width: 6, height: 6)
                            Text("\(deliveries.outForDelivery) out for delivery")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.success)
                        }
                    }
                }
            }

            briefDivider
        }

        // Yesterday's nutrition
        if let nutrition = nutritionSummary(forYesterday: true) {
            briefSection(icon: "fork.knife", title: "Yesterday's Nutrition") {
                HStack(spacing: PerchTheme.Spacing.medium) {
                    if let pct = nutrition.caloriePercent {
                        metricPill(value: "\(pct)%", label: "calories")
                    }
                    if let protein = nutrition.proteinStatus {
                        metricPill(value: protein, label: "protein")
                    }
                }
            }
        }
    }

    // MARK: - Evening Brief

    @ViewBuilder
    private var eveningBrief: some View {
        // Today's nutrition progress
        if let nutrition = nutritionSummary(forYesterday: false) {
            briefSection(icon: "fork.knife", title: "Nutrition") {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                    if let consumed = nutrition.caloriesConsumed, let target = nutrition.caloriesTarget {
                        HStack(spacing: PerchTheme.Spacing.xxSmall) {
                            Text("\(Int(consumed))")
                                .font(PerchTheme.Font.headingNumeric)
                                .foregroundColor(PerchTheme.textPrimary)
                            Text("/ \(Int(target)) kcal")
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }
                    if let protein = nutrition.proteinStatus {
                        Text("Protein: \(protein)")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }
            }

            briefDivider
        }

        // Tomorrow's preview
        if let tomorrow = tomorrowPreview {
            briefSection(icon: "calendar.badge.clock", title: "Tomorrow") {
                if tomorrow.eventCount == 0 {
                    Text("No events scheduled")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                        Text("\(tomorrow.eventCount) event\(tomorrow.eventCount == 1 ? "" : "s")")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                        if let first = tomorrow.firstEvent {
                            Text("\(first.time) — \(first.title)")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            briefDivider
        }

        // Pending deliveries
        if let deliveries = deliverySummary, deliveries.total > 0 {
            briefSection(icon: "shippingbox.fill", title: "Deliveries") {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                    Text("\(deliveries.total) pending")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)
                    if deliveries.outForDelivery > 0 {
                        HStack(spacing: PerchTheme.Spacing.xxSmall) {
                            Circle()
                                .fill(PerchTheme.success)
                                .frame(width: 6, height: 6)
                            Text("\(deliveries.outForDelivery) out for delivery")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.success)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func briefSection<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
            HStack(spacing: PerchTheme.Spacing.xxSmall) {
                Image(systemName: icon)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                Text(title)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                    .textCase(.uppercase)
            }
            content()
        }
    }

    private func metricPill(value: String, label: String, isInteger: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(PerchTheme.Font.headingNumeric)
                .foregroundColor(PerchTheme.textPrimary)
            Text(label)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
        }
        .padding(.horizontal, PerchTheme.Spacing.small)
        .padding(.vertical, PerchTheme.Spacing.xSmall)
        .background(PerchTheme.cardInnerBackground)
        .cornerRadius(PerchTheme.Card.innerCornerRadius)
    }

    private var briefDivider: some View {
        Rectangle()
            .fill(PerchTheme.border)
            .frame(height: 1)
    }

    // MARK: - Data Extraction

    private struct SleepSummaryData {
        let duration: String
        let deepSleep: String?
        let hrv: String?
    }

    private var sleepSummary: SleepSummaryData? {
        let healthRecords = records.filter { $0.category == .health }

        let sleepDuration = healthRecords
            .compactMap { $0.asMeasurement() }
            .filter { $0.metric == "sleep_duration" }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .first

        guard let sleepDuration else { return nil }

        let deepSleep = healthRecords
            .compactMap { $0.asMeasurement() }
            .filter { $0.metric == "deep_sleep" }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .first

        let hrv = healthRecords
            .compactMap { $0.asMeasurement() }
            .filter { $0.metric == "avg_sleep_hrv" }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .first

        let durationStr = formatHours(sleepDuration.value)
        let deepStr = deepSleep.map { formatHours($0.value) }
        let hrvStr = hrv.map { "\(Int($0.value))" }

        return SleepSummaryData(duration: durationStr, deepSleep: deepStr, hrv: hrvStr)
    }

    private struct CalendarSummaryData {
        let eventCount: Int
        let firstEvent: (time: String, title: String)?
    }

    private var calendarSummary: CalendarSummaryData? {
        let todayEvents = records.compactMap { record -> EventData? in
            guard let event = record.asEvent(),
                  Calendar.current.isDateInToday(event.start),
                  event.start > .now else { return nil }
            return event
        }.sorted { $0.start < $1.start }

        let firstEvent = todayEvents.first.map { event in
            (time: PerchFormatters.time24h.string(from: event.start), title: event.title)
        }

        return CalendarSummaryData(eventCount: todayEvents.count, firstEvent: firstEvent)
    }

    private struct DeliverySummaryData {
        let total: Int
        let outForDelivery: Int
    }

    private var deliverySummary: DeliverySummaryData? {
        let activeDeliveries = records.compactMap { $0.asDelivery() }
            .filter {
                let s = $0.status.lowercased()
                return s != "delivered" && s != "cancelled"
            }

        let ofd = activeDeliveries.filter {
            $0.status.lowercased().replacingOccurrences(of: " ", with: "_") == "out_for_delivery"
        }.count

        return DeliverySummaryData(total: activeDeliveries.count, outForDelivery: ofd)
    }

    private struct NutritionSummaryData {
        let caloriePercent: Int?
        let caloriesConsumed: Double?
        let caloriesTarget: Double?
        let proteinStatus: String?
    }

    private func nutritionSummary(forYesterday: Bool) -> NutritionSummaryData? {
        let todayString: String = {
            if forYesterday {
                return PerchFormatters.isoDate.string(from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
            }
            return PerchFormatters.isoDate.string(from: .now)
        }()

        // Find calories record for the target day
        let caloriesRecord = records
            .filter { $0.asMeasurement()?.metric == "daily_calories" }
            .first { $0.asMeasurement()?.context == todayString }
            ?? (forYesterday ? nil : records
                .filter { $0.asMeasurement()?.metric == "daily_calories" }
                .sorted { ($0.asMeasurement()?.timestamp ?? $0.createdAt) > ($1.asMeasurement()?.timestamp ?? $1.createdAt) }
                .first)

        let macrosRecord = records
            .filter { $0.asMacros() != nil }
            .first { $0.asMacros()?.date == todayString }

        guard caloriesRecord != nil || macrosRecord != nil else { return nil }

        var caloriePercent: Int?
        var consumed: Double?
        var target: Double?
        if let m = caloriesRecord?.asMeasurement() {
            consumed = m.value
            target = m.target
            if let t = m.target, t > 0 {
                caloriePercent = Int(m.value / t * 100)
            }
        }

        var proteinStatus: String?
        if let macros = macrosRecord?.asMacros() {
            if let pt = macros.proteinTarget, pt > 0 {
                let pct = Int(macros.protein / pt * 100)
                proteinStatus = "\(pct)%"
            } else {
                proteinStatus = "\(Int(macros.protein))g"
            }
        }

        return NutritionSummaryData(
            caloriePercent: caloriePercent,
            caloriesConsumed: consumed,
            caloriesTarget: target,
            proteinStatus: proteinStatus
        )
    }

    private var tomorrowPreview: CalendarSummaryData? {
        let tomorrowEvents = records.compactMap { record -> EventData? in
            guard let event = record.asEvent(),
                  Calendar.current.isDateInTomorrow(event.start) else { return nil }
            return event
        }.sorted { $0.start < $1.start }

        let firstEvent = tomorrowEvents.first.map { event in
            (time: PerchFormatters.time24h.string(from: event.start), title: event.title)
        }

        return CalendarSummaryData(eventCount: tomorrowEvents.count, firstEvent: firstEvent)
    }

    // MARK: - Helpers

    private func formatHours(_ value: Double) -> String {
        let hours = Int(value)
        let minutes = Int((value - Double(hours)) * 60)
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h\(minutes)m"
    }

    private var briefDateString: String {
        PerchFormatters.weekdayDate.string(from: .now)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DailyBriefCard(records: [])
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
