import SwiftUI

/// Nutrition meal card showing meal timing, macro totals, and inline correction tools.
struct MealCard: View {
    @Environment(\.perchPalette) private var palette

    private let meal: MealRecord?
    private let viewModel: NutritionViewModel?
    private let isShimmer: Bool

    @State private var isExpanded = false
    @State private var showingCorrectionField = false
    @State private var showingManualEditor = false
    @State private var correctionText = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""

    init(meal: MealRecord, viewModel: NutritionViewModel? = nil) {
        self.meal = meal
        self.viewModel = viewModel
        self.isShimmer = false
    }

    init(record: Record, viewModel: NutritionViewModel) {
        self.init(meal: MealRecord(from: record), viewModel: viewModel)
    }

    private init(shimmer: Bool) {
        self.meal = nil
        self.viewModel = nil
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
                            .foregroundColor(palette.ink)
                            .lineLimit(isExpanded ? nil : 2)

                        Text(meal.mealTime.formatted(date: .omitted, time: .shortened))
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(palette.muted)
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
                    .foregroundColor(palette.muted)
                    .lineLimit(isExpanded ? nil : 2)
            }

            if !isShimmer, let meal, isExpanded {
                expandedControls(for: meal)
            } else if !isShimmer {
                Text("Tap to expand.")
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(palette.faint)
            }
        }
        .padding(PerchTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .fill(isExpanded ? palette.chipBg.opacity(0.35) : .clear)
        )
        .cardStyle()
        .contentShape(Rectangle())
        .onTapGesture {
            guard isShimmer == false else { return }
            PerchMotion.withOptionalAnimation {
                isExpanded.toggle()
            }
        }
        .onAppear {
            syncManualFields()
        }
        .onChange(of: meal?.id) { _, _ in
            syncManualFields()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var photoPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.chipBg)
                .frame(width: 64, height: 64)

            if isShimmer {
                SkeletonCircle(size: 22)
            } else {
                Image(systemName: "fork.knife")
                    .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                    .foregroundColor(palette.kinetic)
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
                MacroPill(label: "Cal", value: "\(Int(meal.calories))", tint: palette.kinetic)
                MacroPill(label: "P", value: "\(Int(meal.protein))g", tint: PerchTheme.macroProtein)
                MacroPill(label: "C", value: "\(Int(meal.carbs))g", tint: PerchTheme.macroCarbs)
                MacroPill(label: "F", value: "\(Int(meal.fat))g", tint: PerchTheme.macroFat)
            }
        }
    }

    @ViewBuilder
    private func expandedControls(for meal: MealRecord) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            HStack(spacing: PerchTheme.Spacing.small) {
                actionButton(
                    title: showingCorrectionField ? "Hide Correction" : "Correct",
                    systemImage: "wand.and.stars",
                    tint: palette.kinetic.opacity(0.12),
                    foreground: palette.kinetic
                ) {
                    PerchMotion.withOptionalAnimation {
                        showingCorrectionField.toggle()
                        if showingCorrectionField { showingManualEditor = false }
                    }
                }

                actionButton(
                    title: showingManualEditor ? "Close Editor" : "Edit manually",
                    systemImage: "slider.horizontal.3",
                    tint: palette.chipBg,
                    foreground: palette.ink
                ) {
                    PerchMotion.withOptionalAnimation {
                        showingManualEditor.toggle()
                        if showingManualEditor { showingCorrectionField = false }
                    }
                }
            }

            if showingCorrectionField {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                    TextField("What was different?", text: $correctionText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(palette.ink)
                        .padding(PerchTheme.Spacing.medium)
                        .background(
                            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                .fill(palette.chipBg)
                        )
                        .onSubmit {
                            submitCorrection()
                        }

                    HStack {
                        Spacer()
                        Button("Submit correction") {
                            submitCorrection()
                        }
                        .font(PerchTheme.Font.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(palette.kinetic)
                        .disabled(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel?.isAnalyzing == true)
                    }
                }
            }

            if showingManualEditor {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                    Text("Edit macros")
                        .font(PerchTheme.Font.cardEyebrow)
                        .foregroundColor(palette.muted)

                    HStack(spacing: PerchTheme.Spacing.small) {
                        manualField(title: "Cal", value: $caloriesText)
                        manualField(title: "P", value: $proteinText)
                        manualField(title: "C", value: $carbsText)
                        manualField(title: "F", value: $fatText)
                    }

                    HStack {
                        Spacer()
                        Button("Save edits") {
                            submitManualEdit(for: meal)
                        }
                        .font(PerchTheme.Font.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(palette.kinetic)
                        .disabled(viewModel?.isAnalyzing == true || parsedManualValues == nil)
                    }
                }
                .padding(PerchTheme.Spacing.medium)
                .background(
                    RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                        .fill(palette.chipBg.opacity(0.85))
                )
            }
            Text("Tap anywhere on the card to collapse.")
                .font(PerchTheme.Font.micro)
                .foregroundColor(palette.faint)
        }
    }

    private var correctedBadge: some View {
        Text("Corrected")
            .font(PerchTheme.Font.micro)
            .foregroundColor(palette.wellness)
            .padding(.horizontal, PerchTheme.Spacing.small)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(palette.wellness.opacity(0.12))
            )
    }

    private var accessibilityLabel: String {
        guard let meal else { return "Loading meal" }
        return "\(meal.mealName), \(Int(meal.calories)) calories, \(Int(meal.protein)) grams protein, \(Int(meal.carbs)) grams carbs, \(Int(meal.fat)) grams fat"
    }

    @ViewBuilder
    private func manualField(title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
            Text(title)
                .font(PerchTheme.Font.micro)
                .foregroundColor(palette.muted)

            TextField(title, text: value)
                .keyboardType(.decimalPad)
                .font(PerchTheme.Font.bodyNumeric)
                .foregroundColor(palette.ink)
                .padding(.horizontal, PerchTheme.Spacing.small)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(PerchTheme.background.opacity(0.75))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(PerchTheme.Font.caption)
                .fontWeight(.semibold)
                .foregroundColor(foreground)
                .padding(.horizontal, PerchTheme.Spacing.medium)
                .padding(.vertical, PerchTheme.Spacing.small)
                .background(
                    Capsule()
                        .fill(tint)
                )
        }
        .buttonStyle(.plain)
    }

    private var parsedManualValues: (Double, Double, Double, Double)? {
        guard
            let calories = Double(caloriesText),
            let protein = Double(proteinText),
            let carbs = Double(carbsText),
            let fat = Double(fatText)
        else {
            return nil
        }

        return (calories, protein, carbs, fat)
    }

    private func submitCorrection() {
        guard let meal else { return }
        let trimmed = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        Task {
            await viewModel?.correctMeal(recordId: meal.id.uuidString, correction: trimmed)
            await MainActor.run {
                correctionText = ""
                showingCorrectionField = false
            }
        }
    }

    private func submitManualEdit(for meal: MealRecord) {
        guard let values = parsedManualValues else { return }

        Task {
            await viewModel?.updateMealMacros(
                recordId: meal.id,
                calories: values.0,
                protein: values.1,
                carbs: values.2,
                fat: values.3
            )
            await MainActor.run {
                showingManualEditor = false
            }
        }
    }

    private func syncManualFields() {
        guard let meal else { return }
        caloriesText = String(Int(meal.calories))
        proteinText = String(Int(meal.protein))
        carbsText = String(Int(meal.carbs))
        fatText = String(Int(meal.fat))
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
                .foregroundColor(palette.muted)

            Text(value)
                .font(PerchTheme.Font.captionNumeric)
                .foregroundColor(palette.ink)
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
