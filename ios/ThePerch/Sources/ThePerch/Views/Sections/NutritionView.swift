import SwiftUI

/// Nutrition section showing daily meal history, corrections, and suggestions.
struct NutritionView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel

    @State private var viewModel = NutritionViewModel()
    @State private var cardsAppeared = false
    @State private var showingInputSheet = false
    @State private var showingSuggestionsSheet = false

    private var nutritionRecords: [Record] {
        dashboardViewModel.recordsBySlug[RecordCategory.nutrition.rawValue] ?? []
    }

    private var submissionUserId: String {
        nutritionRecords.first?.userId.uuidString ?? AppConfig.defaultUserID.uuidString
    }

    var body: some View {
        @Bindable var vm = viewModel

        ZStack(alignment: .bottomTrailing) {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    SectionHeader(title: "Nutrition", freshnessKey: "nutrition")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    if let error = vm.error {
                        ErrorBanner(
                            message: error,
                            retryAction: { Task { await dashboardViewModel.refreshRecords(forceRefresh: true) } },
                            onDismiss: { vm.error = nil }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    content

                    Color.clear
                        .frame(height: 0)
                        .onAppear {
                            PerchMotion.withOptionalAnimation { cardsAppeared = true }
                        }

                    Spacer()
                        .frame(height: 148)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.refreshRecords(forceRefresh: true)
                PerchHaptics.success()
            }

            floatingActions
        }
        .onChange(of: dashboardViewModel.allRecords) { _, newRecords in
            vm.loadMeals(from: newRecords)
        }
        .onAppear {
            vm.loadMeals(from: dashboardViewModel.allRecords)
        }
        .sheet(isPresented: $showingInputSheet) {
            MealInputSheet(isSubmitting: vm.isAnalyzing) { text, image in
                let didSubmit = await vm.logMeal(text: text, image: image, userId: submissionUserId)
                if didSubmit {
                    await dashboardViewModel.refreshRecords(forceRefresh: true)
                }
                return didSubmit
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSuggestionsSheet, onDismiss: {
            vm.clearSuggestions()
        }) {
            MealSuggestionsSheet(
                viewModel: vm,
                userId: submissionUserId,
                onLogSuggestion: { suggestion in
                    let didSubmit = await vm.logSuggestedMeal(suggestion, userId: submissionUserId)
                    if didSubmit {
                        await dashboardViewModel.refreshRecords(forceRefresh: true)
                        showingSuggestionsSheet = false
                    }
                    return didSubmit
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        if dashboardViewModel.isLoading && viewModel.meals.isEmpty {
            VStack(spacing: PerchTheme.Spacing.medium) {
                DailySummaryBar.shimmer
                ForEach(0..<3, id: \.self) { index in
                    MealCard.shimmer
                        .cardAppear(index: index + 1, appeared: cardsAppeared)
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else if viewModel.meals.isEmpty {
            EmptyStateView(
                icon: "fork.knife",
                title: "No meals logged",
                subtitle: "Add your first meal to start tracking calories and macros for the day.",
                actionTitle: "Log a meal",
                action: { showingInputSheet = true }
            )
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else {
            LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                ForEach(Array(viewModel.visibleSections.enumerated()), id: \.element.id) { index, section in
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                        NutritionDayHeader(date: section.date)
                        DailySummaryBar(summary: section.summary, title: summaryTitle(for: section.date))

                        ForEach(Array(section.meals.enumerated()), id: \.element.id) { mealIndex, meal in
                            MealCard(meal: meal, viewModel: viewModel)
                                .cardAppear(index: index + mealIndex + 1, appeared: cardsAppeared)
                        }
                    }
                    .onAppear {
                        viewModel.loadHistoryIfNeeded(for: section.date)
                    }
                }

                if viewModel.visibleSections.count < viewModel.daySections.count {
                    HStack {
                        Spacer()
                        ProgressView("Loading more days...")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.vertical, PerchTheme.Spacing.small)
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        }
    }

    private var floatingActions: some View {
        VStack(alignment: .trailing, spacing: PerchTheme.Spacing.small) {
            Button {
                showingSuggestionsSheet = true
            } label: {
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "sparkles")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                    Text("What should I eat?")
                        .font(PerchTheme.Font.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(PerchTheme.textPrimary)
                .padding(.horizontal, PerchTheme.Spacing.medium)
                .padding(.vertical, PerchTheme.Spacing.small)
                .background(
                    Capsule()
                        .fill(PerchTheme.cardBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(PerchTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                showingInputSheet = true
            } label: {
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "plus")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                    Text("Log Meal")
                        .font(PerchTheme.Font.body)
                        .fontWeight(.semibold)
                }
                .foregroundColor(PerchTheme.accentForeground)
                .padding(.horizontal, PerchTheme.Spacing.medium)
                .padding(.vertical, PerchTheme.Spacing.small)
                .background(
                    Capsule()
                        .fill(PerchTheme.accent)
                )
                .shadow(color: PerchTheme.accent.opacity(0.28), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, PerchTheme.Spacing.large)
        .padding(.bottom, PerchTheme.Spacing.large)
    }

    private func summaryTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "TODAY'S TOTAL"
        }
        if calendar.isDateInYesterday(date) {
            return "YESTERDAY'S TOTAL"
        }
        return "\(PerchFormatters.weekday.string(from: date).uppercased()) TOTAL"
    }
}

private struct NutritionDayHeader: View {
    let date: Date

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return PerchFormatters.weekdayDate.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxxSmall) {
            Text(title.uppercased())
                .font(PerchTheme.Font.cardEyebrow)
                .foregroundColor(PerchTheme.textSecondary)
                .tracking(0.8)

            Text(PerchFormatters.mediumDate.string(from: date))
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
        }
    }
}

private struct MealSuggestionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: NutritionViewModel
    let userId: String
    let onLogSuggestion: (MealSuggestion) async -> Bool

    @State private var context = ""

    private var trimmedContext: String? {
        let value = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    Text("Ask for meal ideas based on where you are, what you can cook, or what kind of meal fits right now.")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)

                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                        Text("Context")
                            .font(PerchTheme.Font.cardEyebrow)
                            .foregroundColor(PerchTheme.textSecondary)

                        TextField("I'm at a food court", text: $context, axis: .vertical)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                            .lineLimit(2...4)
                            .padding(PerchTheme.Spacing.medium)
                            .background(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                    .fill(PerchTheme.cardInnerBackground)
                            )
                    }

                    Button {
                        Task {
                            await viewModel.requestSuggestions(userId: userId, context: trimmedContext)
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoadingSuggestions {
                                ProgressView()
                                    .tint(PerchTheme.accentForeground)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(viewModel.mealSuggestions.isEmpty ? "Get suggestions" : "Refresh suggestions")
                                .fontWeight(.semibold)
                        }
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.accentForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PerchTheme.Spacing.medium)
                        .background(
                            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                .fill(PerchTheme.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoadingSuggestions)

                    if !viewModel.mealSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Suggestions")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            ForEach(viewModel.mealSuggestions.prefix(3)) { suggestion in
                                SuggestionCard(suggestion: suggestion) {
                                    let didLog = await onLogSuggestion(suggestion)
                                    if didLog {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(PerchTheme.Spacing.large)
            }
            .background(PerchTheme.background.ignoresSafeArea())
            .navigationTitle("What should I eat?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(PerchTheme.textSecondary)
                }
            }
        }
    }
}

private struct SuggestionCard: View {
    let suggestion: MealSuggestion
    let onLog: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                Text(suggestion.mealName)
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text(suggestion.analysisLine)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
            }

            HStack(spacing: PerchTheme.Spacing.small) {
                SuggestionMacroPill(label: "Cal", value: "\(Int(suggestion.calories))", tint: PerchTheme.accent)
                SuggestionMacroPill(label: "P", value: "\(Int(suggestion.protein))g", tint: PerchTheme.macroProtein)
                SuggestionMacroPill(label: "C", value: "\(Int(suggestion.carbs))g", tint: PerchTheme.macroCarbs)
                SuggestionMacroPill(label: "F", value: "\(Int(suggestion.fat))g", tint: PerchTheme.macroFat)
            }

            Button("Log this") {
                Task {
                    await onLog()
                }
            }
            .font(PerchTheme.Font.caption)
            .fontWeight(.semibold)
            .foregroundColor(PerchTheme.accent)
        }
        .padding(PerchTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .fill(PerchTheme.cardBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .stroke(PerchTheme.border.opacity(0.8), lineWidth: 1)
        )
    }
}

private struct SuggestionMacroPill: View {
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

#Preview {
    NutritionView()
        .environment(DashboardViewModel())
}
