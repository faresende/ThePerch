import SwiftUI

/// Compact nutrition summary with calorie target and macro progress bars.
struct DailySummaryBar: View {
    private let summary: DailyNutritionSummary?
    private let isShimmer: Bool

    init(summary: DailyNutritionSummary) {
        self.summary = summary
        self.isShimmer = false
    }

    private init(shimmer: Bool) {
        self.summary = nil
        self.isShimmer = shimmer
    }

    static var shimmer: some View {
        DailySummaryBar(shimmer: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                if isShimmer {
                    SkeletonLine(width: 120, height: 14)
                    Spacer()
                    SkeletonLine(width: 92, height: 18)
                } else if let summary {
                    Text("TODAY'S TOTAL")
                        .font(PerchTheme.Font.cardEyebrow)
                        .foregroundColor(PerchTheme.textSecondary)
                        .tracking(0.8)

                    Spacer()

                    Text("\(Int(summary.consumed.calories)) / \(Int(summary.targets.calories)) kcal")
                        .font(PerchTheme.Font.headingNumeric)
                        .foregroundColor(PerchTheme.textPrimary)
                }
            }

            calorieProgress

            HStack(spacing: PerchTheme.Spacing.small) {
                if isShimmer {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonRect(height: 52, cornerRadius: 14)
                    }
                } else if let summary {
                    MacroProgressMetric(
                        label: "Protein",
                        shortLabel: "P",
                        consumed: summary.consumed.protein,
                        target: summary.targets.protein,
                        tint: PerchTheme.macroProtein
                    )
                    MacroProgressMetric(
                        label: "Carbs",
                        shortLabel: "C",
                        consumed: summary.consumed.carbs,
                        target: summary.targets.carbs,
                        tint: PerchTheme.macroCarbs
                    )
                    MacroProgressMetric(
                        label: "Fat",
                        shortLabel: "F",
                        consumed: summary.consumed.fat,
                        target: summary.targets.fat,
                        tint: PerchTheme.macroFat
                    )
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private var calorieProgress: some View {
        if isShimmer {
            SkeletonRect(height: 10, cornerRadius: 5)
        } else if let summary {
            let progress = clampedProgress(summary.consumed.calories, summary.targets.calories)

            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(PerchTheme.cardInnerBackground)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [PerchTheme.accent.opacity(0.65), PerchTheme.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 10)

                Text("\(Int(progress * 100))% of target")
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(PerchTheme.textTertiary)
            }
        }
    }

    private func clampedProgress(_ consumed: Double, _ target: Double) -> CGFloat {
        guard target > 0 else { return 0 }
        return CGFloat(min(max(consumed / target, 0), 1))
    }
}

private struct MacroProgressMetric: View {
    let label: String
    let shortLabel: String
    let consumed: Double
    let target: Double
    let tint: Color

    private var progress: CGFloat {
        guard target > 0 else { return 0 }
        return CGFloat(min(max(consumed / target, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
            HStack {
                Text(shortLabel)
                    .font(PerchTheme.Font.cardEyebrow)
                    .foregroundColor(tint)
                Spacer()
                Text("\(Int(consumed))/\(Int(target))g")
                    .font(PerchTheme.Font.microNumeric)
                    .foregroundColor(PerchTheme.textSecondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PerchTheme.cardInnerBackground)
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 8)

            Text(label)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
        }
        .padding(.horizontal, PerchTheme.Spacing.small)
        .padding(.vertical, PerchTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PerchTheme.cardInnerBackground.opacity(0.65))
        )
    }
}

#Preview {
    VStack(spacing: PerchTheme.Spacing.medium) {
        DailySummaryBar(
            summary: DailyNutritionSummary(
                consumed: NutritionTargets(calories: 1840, protein: 121, carbs: 165, fat: 58),
                targets: NutritionTargets(calories: 2600, protein: 180, carbs: 250, fat: 80)
            )
        )

        DailySummaryBar.shimmer
    }
    .padding()
    .background(PerchTheme.background)
}
