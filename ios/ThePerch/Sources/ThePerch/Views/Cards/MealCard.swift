import SwiftUI

/// Nutrition meal card showing meal timing, macro totals, and analysis output.
struct MealCard: View {
    private let meal: MealRecord?
    private let isShimmer: Bool

    init(meal: MealRecord) {
        self.meal = meal
        self.isShimmer = false
    }

    private init(shimmer: Bool) {
        self.meal = nil
        self.isShimmer = shimmer
    }

    static var shimmer: some View {
        MealCard(shimmer: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: PerchTheme.Spacing.medium) {
                photoPlaceholder

                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                    if isShimmer {
                        SkeletonLine(width: 132, height: 16)
                        SkeletonLine(width: 72, height: 12)
                    } else if let meal {
                        Text(meal.mealName)
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)
                            .lineLimit(2)

                        Text(meal.mealTime.formatted(date: .omitted, time: .shortened))
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                if isShimmer {
                    SkeletonRect(width: 78, height: 24, cornerRadius: 12)
                } else if meal?.corrected == true {
                    correctedBadge
                }
            }

            macroRow

            if isShimmer {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                    SkeletonLine(height: 12)
                    SkeletonLine(width: 180, height: 12)
                }
            } else if let meal, !meal.analysis.isEmpty {
                Text(meal.analysis)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(PerchTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var photoPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(PerchTheme.cardInnerBackground)
                .frame(width: 64, height: 64)

            if isShimmer {
                SkeletonCircle(size: 22)
            } else {
                Image(systemName: "fork.knife")
                    .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                    .foregroundColor(PerchTheme.accent)
            }
        }
        .shimmer(if: isShimmer)
    }

    @ViewBuilder
    private var macroRow: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            if isShimmer {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonRect(width: 62, height: 28, cornerRadius: 14)
                }
            } else if let meal {
                MacroPill(label: "Cal", value: "\(Int(meal.calories))", tint: PerchTheme.accent)
                MacroPill(label: "P", value: "\(Int(meal.protein))g", tint: PerchTheme.macroProtein)
                MacroPill(label: "C", value: "\(Int(meal.carbs))g", tint: PerchTheme.macroCarbs)
                MacroPill(label: "F", value: "\(Int(meal.fat))g", tint: PerchTheme.macroFat)
            }
        }
    }

    private var correctedBadge: some View {
        Text("Corrected")
            .font(PerchTheme.Font.micro)
            .foregroundColor(PerchTheme.success)
            .padding(.horizontal, PerchTheme.Spacing.small)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(PerchTheme.success.opacity(0.12))
            )
    }

    private var accessibilityLabel: String {
        guard let meal else { return "Loading meal" }
        return "\(meal.mealName), \(Int(meal.calories)) calories, \(Int(meal.protein)) grams protein, \(Int(meal.carbs)) grams carbs, \(Int(meal.fat)) grams fat"
    }
}

private struct MacroPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textSecondary)

            Text(value)
                .font(PerchTheme.Font.captionNumeric)
                .foregroundColor(PerchTheme.textPrimary)
        }
        .padding(.horizontal, PerchTheme.Spacing.small)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private extension View {
    @ViewBuilder
    func shimmer(if isActive: Bool) -> some View {
        if isActive {
            self.shimmer()
        } else {
            self
        }
    }
}

#Preview {
    VStack(spacing: PerchTheme.Spacing.medium) {
        MealCard(
            meal: MealRecord(
                from: Record(
                    id: UUID(),
                    agentId: "nutrition",
                    userId: UUID(),
                    type: .meal,
                    category: .nutrition,
                    title: "Salmon bowl",
                    data: .object([
                        "meal_name": .string("Salmon bowl"),
                        "calories": .number(680),
                        "protein": .number(42),
                        "carbs": .number(58),
                        "fat": .number(24),
                        "analysis": .string("High-protein lunch with a moderate carb load."),
                        "corrected": .bool(true),
                        "meal_time": .string(ISO8601DateFormatter().string(from: .now)),
                    ]),
                    displayHint: .unknown,
                    annotations: nil,
                    pinned: false,
                    createdAt: .now,
                    updatedAt: .now,
                    expiresAt: nil
                )
            )
        )

        MealCard.shimmer
    }
    .padding()
    .background(PerchTheme.background)
}
