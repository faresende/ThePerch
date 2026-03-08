import SwiftUI

/// Unified nutrition card combining calories and macros.
/// Morning (before 14:00): Shows yesterday's final tally.
/// Afternoon (14:00+): Shows today's live progress.
struct NutritionHomeCard: View {
    let records: [Record]

    @State private var animatedProgress: Double = 0
    @State private var animateMacros = false

    private var isMorning: Bool {
        Calendar.current.component(.hour, from: .now) < 14
    }

    private var dateString: String {
        if isMorning {
            return PerchFormatters.isoDate.string(from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
        }
        return PerchFormatters.isoDate.string(from: .now)
    }

    private var caloriesData: MeasurementData? {
        let caloriesRecords = records
            .filter { $0.asMeasurement()?.metric == "daily_calories" }

        // Try exact date match first
        if let match = caloriesRecords.first(where: { $0.asMeasurement()?.context == dateString }) {
            return match.asMeasurement()
        }

        // For today (afternoon), fall back to most recent
        if !isMorning {
            return caloriesRecords
                .compactMap { $0.asMeasurement() }
                .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
                .first
        }

        return nil
    }

    private var macrosData: MacrosData? {
        records
            .compactMap { $0.asMacros() }
            .first { $0.date == dateString }
    }

    private var hasData: Bool {
        caloriesData != nil || macrosData != nil
    }

    private var consumed: Double { caloriesData?.value ?? 0 }
    private var target: Double { caloriesData?.target ?? 0 }
    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(consumed / target, 1.5)
    }

    private var progressColor: Color {
        if consumed > target * 1.1 { return PerchTheme.error }
        if consumed > target * 0.9 { return PerchTheme.success }
        return PerchTheme.accent
    }

    // Macro colors
    private static let proteinColor = Color(red: 0.35, green: 0.6, blue: 0.95)
    private static let carbsColor = PerchTheme.accent
    private static let fatColor = Color(red: 0.9, green: 0.55, blue: 0.6)

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Header
            HStack(spacing: PerchTheme.Spacing.xSmall) {
                Image(systemName: "fork.knife")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.accent)
                Text(isMorning ? "YESTERDAY'S NUTRITION" : "NUTRITION")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
                    .textCase(.uppercase)
                Spacer()
            }

            if !hasData {
                // Empty state
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "fork.knife")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.large))
                        .foregroundColor(PerchTheme.textTertiary)
                    Text("No meals logged yet")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, PerchTheme.Spacing.small)
            } else {
                HStack(spacing: PerchTheme.Spacing.large) {
                    // Calorie ring
                    if caloriesData != nil {
                        calorieRing
                    }

                    // Stats
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                        if target > 0 {
                            HStack {
                                Text("Target")
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textSecondary)
                                Spacer()
                                Text("\(Int(target)) kcal")
                                    .font(PerchTheme.Font.captionNumeric)
                                    .foregroundColor(PerchTheme.textPrimary)
                            }
                            HStack {
                                Text("Remaining")
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textSecondary)
                                Spacer()
                                let remaining = max(target - consumed, 0)
                                Text("\(Int(remaining)) kcal")
                                    .font(PerchTheme.Font.captionNumeric)
                                    .foregroundColor(remaining > 0 ? PerchTheme.accent : PerchTheme.error)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Macro bars
                if let macros = macrosData {
                    VStack(spacing: PerchTheme.Spacing.xSmall) {
                        macroBar(label: "Protein", value: macros.protein, target: macros.proteinTarget, color: Self.proteinColor)
                        macroBar(label: "Carbs", value: macros.carbs, target: macros.carbsTarget, color: Self.carbsColor)
                        macroBar(label: "Fat", value: macros.fat, target: macros.fatTarget, color: Self.fatColor)
                    }
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .onAppear {
            PerchMotion.withOptionalAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animatedProgress = progress
                animateMacros = true
            }
        }
    }

    // MARK: - Calorie Ring

    private var calorieRing: some View {
        ZStack {
            Circle()
                .stroke(PerchTheme.border, lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(animatedProgress, 1.0))
                .stroke(
                    AngularGradient(
                        colors: [progressColor.opacity(0.5), progressColor],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * min(progress, 1.0))
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: progressColor.opacity(0.4), radius: 6)

            VStack(spacing: 2) {
                Text("\(Int(consumed))")
                    .font(PerchTheme.Font.titleNumeric)
                    .foregroundColor(PerchTheme.textPrimary)
                Text("kcal")
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(PerchTheme.textTertiary)
            }
        }
        .frame(width: 90, height: 90)
    }

    // MARK: - Macro Bar

    private func macroBar(label: String, value: Double, target: Double?, color: Color) -> some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
            }
            .frame(width: 70, alignment: .leading)

            GeometryReader { geometry in
                let ratio: CGFloat = {
                    guard let target, target > 0 else { return 0 }
                    return CGFloat(min(value / target, 1.0))
                }()
                let animatedWidth = animateMacros ? geometry.size.width * ratio : 0

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PerchTheme.cardInnerBackground)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: animatedWidth, height: 6)
                }
            }
            .frame(height: 6)

            if let target {
                Text("\(Int(value))/\(Int(target))g")
                    .font(PerchTheme.Font.microNumeric)
                    .foregroundColor(PerchTheme.textTertiary)
                    .frame(width: 65, alignment: .trailing)
            } else {
                Text("\(Int(value))g")
                    .font(PerchTheme.Font.microNumeric)
                    .foregroundColor(PerchTheme.textTertiary)
                    .frame(width: 65, alignment: .trailing)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        NutritionHomeCard(records: [])
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
