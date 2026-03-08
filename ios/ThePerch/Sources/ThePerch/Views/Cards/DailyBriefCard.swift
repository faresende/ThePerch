import SwiftUI

/// A synthesized daily summary card that appears at the top of HomeView.
/// Shows a morning brief (before 14:00) or evening brief (after 14:00).
/// Accepts pre-computed DailyBriefData — no filtering/decoding in the view body.
struct DailyBriefCard: View {
    let data: DailyBriefData

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
        if let sleep = data.sleepSummary {
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
        if let cal = data.calendarSummary {
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
                        if let time = cal.firstEventTime, let title = cal.firstEventTitle {
                            Text("\(time) — \(title)")
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
        if let deliveries = data.deliverySummary, deliveries.total > 0 {
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
        if let nutrition = data.nutritionYesterday {
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
        if let nutrition = data.nutritionToday {
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
        if let tomorrow = data.tomorrowPreview {
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
                        if let time = tomorrow.firstEventTime, let title = tomorrow.firstEventTitle {
                            Text("\(time) — \(title)")
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
        if let deliveries = data.deliverySummary, deliveries.total > 0 {
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

    private var briefDateString: String {
        PerchFormatters.weekdayDate.string(from: .now)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DailyBriefCard(data: DailyBriefData(
            sleepSummary: nil,
            calendarSummary: nil,
            deliverySummary: nil,
            nutritionYesterday: nil,
            nutritionToday: nil,
            tomorrowPreview: nil
        ))
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
